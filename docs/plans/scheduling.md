# Plan: Scheduling

## Context

Nanobot.rb reacts to messages — a user sends something on Slack or CLI and the agent responds. But a genuinely useful assistant also acts on its own schedule: "remind me to call John in 30 minutes", "summarize the news every morning at 8am", "check my email every hour and flag anything urgent."

The original Python nanobot (HKUDS/nanobot) already has this via its `nanobot/cron/` module with three schedule kinds (`at`, `every`, `cron`), JSON persistence, and a callback-based firing model. This plan ports that concept to nanobot.rb, adapted to fit the existing Ruby architecture.

**Scope note**: `docs/goals.md` currently lists "scheduled tasks" under fork territory. This plan moves it into core. The file will be updated accordingly.

## Architecture

The scheduler is a **standalone module** at `lib/nanobot/scheduler/`, peer to `channels/` and `agent/`. It is not a channel — it doesn't receive external messages. It's an internal timer that generates synthetic `InboundMessage`s on the bus, so the agent loop processes them with zero changes to the core processing pipeline.

```
              +-----------+
              |  Config   |  (new: SchedulerConfig)
              +-----+-----+
                    |
     +--------------+--------------+
     |              |              |
+----+-----+  +----+----+  +------+------+
| Channels |  | Agent   |  | Scheduler   |  <- NEW
| Manager  |  | Loop    |  | Service     |
+----+-----+  +----+----+  +------+------+
     |              |              |
     +--------------+--------------+
                    |
              +-----+-----+
              | MessageBus |
              +-----------+
```

### How it works end-to-end

1. User says "remind me every morning at 8am to check my calendar"
2. The agent calls `schedule_add` (an RubyLLM::Tool) with `kind: "cron"`, `expression: "0 8 * * *"`, and the prompt
3. The tool delegates to `ScheduleStore`, which validates via `fugit`, persists to `~/.nanobot/schedules.json`, and computes `next_run_at`
4. `SchedulerService` runs a background thread that ticks every 15s, finds due schedules, and publishes `InboundMessage`s to the bus
5. The agent loop processes these like any other message
6. For jobs with a `deliver_to` target (e.g., "remind me on Slack"), the service subscribes to outbound messages on the `"scheduler"` channel and re-publishes them to the real target channel

### Response routing detail

When a scheduled job fires, the agent's response goes to the `"scheduler"` outbound channel (since `InboundMessage.channel` is `"scheduler"`). The service's `subscribe_outbound("scheduler")` callback intercepts this, looks up the schedule's `deliver_to`, and re-publishes an `OutboundMessage` with the real target channel/chat_id. This piggybacks on the existing bus dispatch with no modifications.

If `deliver_to` is nil, the response is logged and discarded -- the job was fire-and-forget (e.g., "write a daily summary to memory").

## Schedule Kinds

Following the Python version, three kinds:

| Kind | Expression | Example | Behavior |
|------|-----------|---------|----------|
| `at` | ISO 8601 timestamp | `2026-02-17T15:30:00-05:00` | One-shot, auto-disables after firing |
| `every` | Duration string | `30m`, `2h`, `1d` | Recurring, advances by duration |
| `cron` | Cron expression + optional TZ | `0 8 * * *` | Recurring, uses fugit for next time |

## Data Model

`Schedule` struct with: `id` (UUID), `kind`, `expression`, `timezone`, `prompt`, `deliver_to` (hash with channel + chat_id, or nil), `enabled`, `created_at`, `last_run_at`, `next_run_at`.

Persisted as JSON at `~/.nanobot/schedules.json` (consistent with sessions at `~/.nanobot/sessions/`). Loaded on startup, saved on every mutation. File writes are atomic (write to temp + rename) and protected by a mutex.

## File Changes

### New files (6)

| File | Purpose |
|------|---------|
| `lib/nanobot/scheduler/store.rb` | `ScheduleStore` -- CRUD, validation via fugit, JSON persistence |
| `lib/nanobot/scheduler/service.rb` | `SchedulerService` -- background tick thread, fires due jobs via bus, routes responses |
| `lib/nanobot/agent/tools/schedule.rb` | `ScheduleAdd`, `ScheduleList`, `ScheduleRemove` -- RubyLLM::Tool subclasses |
| `spec/scheduler/store_spec.rb` | Store unit tests |
| `spec/scheduler/service_spec.rb` | Service unit tests |
| `spec/agent/tools/schedule_spec.rb` | Tool unit tests |

### Modified files (6)

| File | Change |
|------|--------|
| `lib/nanobot.rb` | Add requires for scheduler modules |
| `lib/nanobot/config/schema.rb` | Add `SchedulerConfig` struct (enabled, tick_interval), wire into root Config |
| `lib/nanobot/agent/loop.rb` | Accept `schedule_store:` kwarg; register schedule tools when store is present |
| `lib/nanobot/cli/commands.rb` | Create store + service in `serve`; pass store to agent loop; stop service on signal |
| `nanobot.gemspec` | Add `fugit` (~> 1.8) dependency |
| `docs/goals.md` | Move "scheduled tasks" from fork territory into core features |

## Phases

### Phase 1: Data layer -- `ScheduleStore`

Build and test `lib/nanobot/scheduler/store.rb` in isolation. This is the foundation everything else depends on.

- `add(kind:, expression:, prompt:, ...)` -- validate with fugit, compute next_run_at, persist
- `remove(id)`, `get(id)`, `list`, `update(id, **attrs)`
- `due_schedules(now)` -- returns enabled schedules where `next_run_at <= now`
- `advance!(schedule, now)` -- updates last_run_at, computes next next_run_at (or disables for `at` jobs)
- JSON load/save with atomic writes

Also add `fugit` to gemspec and the scheduler requires to `lib/nanobot.rb`.

### Phase 2: Scheduler service -- `SchedulerService`

Build and test `lib/nanobot/scheduler/service.rb`.

- `start` / `stop` lifecycle, `running?`
- Background thread with configurable tick interval
- On each tick: call `store.due_schedules`, fire each by publishing `InboundMessage` to bus, then `advance!`
- Response routing: subscribe to `"scheduler"` outbound, re-publish to deliver_to target
- Error handling: rescue per-tick and per-fire, log and continue

### Phase 3: LLM tools

Build and test `lib/nanobot/agent/tools/schedule.rb`.

- `ScheduleAdd` -- accepts kind, expression, prompt, optional timezone and deliver target
- `ScheduleList` -- returns formatted list of all schedules with status
- `ScheduleRemove` -- removes by full or partial ID match
- All delegate to the shared `ScheduleStore` instance

### Phase 4: Config and CLI wiring

Wire everything together:

- `SchedulerConfig` struct in config schema (enabled: true, tick_interval: 15)
- `Loop#initialize` accepts `schedule_store:`, registers tools only when present
- `serve` command creates store + service, passes store to agent loop, starts service after channels, stops on signal
- Schedule tools are **only available in serve mode** -- in CLI `agent` mode the service isn't running so registering the tools would be misleading

### Phase 5: Documentation

Update `docs/goals.md` to move scheduling into core.

## Testing Strategy

Follow existing patterns: `instance_double` for mocks, `Dir.mktmpdir` for filesystem isolation, `Timecop.freeze` for time control, `test_logger` helper.

**Store tests**: CRUD, validation (bad expressions), persistence round-trip, due_schedules with frozen time, advance! behavior per kind, thread safety.

**Service tests**: start/stop lifecycle, tick fires due jobs (mock store), response routing to target channel, error resilience (store raises -> service continues), configurable tick interval.

**Tool tests**: ScheduleAdd success and validation errors, ScheduleList empty and populated, ScheduleRemove by full and partial ID.

**Integration**: Update `loop_spec.rb` (tools registered when store present, not when absent), `schema_spec.rb` (SchedulerConfig defaults), `commands_spec.rb` (serve wires scheduler).

## Verification

1. `bundle exec rspec` -- all tests pass, coverage stays above 95%
2. `bundle exec rubocop` -- no new violations
3. Manual end-to-end: `nanobot serve -d`, send "set a timer for 1 minute", observe agent call schedule_add, wait for firing, verify response

## Dependency

`fugit` (~> 1.8) -- standard Ruby library for cron/duration/timestamp parsing. Used by rufus-scheduler and sidekiq-cron. Pulls in `raabro` and `et-orbi` (lightweight, no native extensions).
