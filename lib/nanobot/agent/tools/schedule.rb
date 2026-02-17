# frozen_string_literal: true

require 'ruby_llm'

module Nanobot
  module Agent
    module Tools
      # Tool for creating scheduled tasks
      class ScheduleAdd < RubyLLM::Tool
        description 'Create a scheduled task. Use kind "at" for one-time (ISO 8601 timestamp), ' \
                    '"every" for recurring intervals ("30m", "2h", "1d"), or ' \
                    '"cron" for cron expressions ("0 8 * * *"). ' \
                    'The prompt is the instruction the agent will execute when the schedule fires.'
        param :kind, desc: 'Schedule type: "at", "every", or "cron"', required: true
        param :expression,
              desc: 'Time expression (ISO 8601 timestamp, duration like "30m", or cron like "0 8 * * *")',
              required: true
        param :prompt, desc: 'Instruction for the agent to execute at the scheduled time', required: true
        param :timezone, desc: 'IANA timezone for cron schedules (e.g., "America/New_York")', required: false
        param :deliver_channel, desc: 'Channel to deliver the response to (e.g., "slack", "telegram")', required: false
        param :deliver_chat_id, desc: 'Chat ID to deliver the response to', required: false

        # @param store [Scheduler::ScheduleStore] shared schedule store
        def initialize(store:)
          super()
          @store = store
        end

        def execute(kind:, expression:, prompt:, timezone: nil, deliver_channel: nil, deliver_chat_id: nil)
          deliver_to = { channel: deliver_channel, chat_id: deliver_chat_id } if deliver_channel && deliver_chat_id

          schedule = @store.add(
            kind: kind,
            expression: expression,
            prompt: prompt,
            timezone: timezone,
            deliver_to: deliver_to
          )

          "Created schedule #{schedule.id} (#{schedule.kind}: #{schedule.expression}). " \
            "Next run: #{schedule.next_run_at}"
        rescue ArgumentError => e
          "Error creating schedule: #{e.message}"
        end
      end

      # Tool for listing all scheduled tasks
      class ScheduleList < RubyLLM::Tool
        description 'List all scheduled tasks with their status, next run time, and prompt'

        # @param store [Scheduler::ScheduleStore] shared schedule store
        def initialize(store:)
          super()
          @store = store
        end

        def execute
          schedules = @store.list
          return 'No scheduled tasks.' if schedules.empty?

          lines = schedules.map do |s|
            status = s.enabled ? 'active' : 'disabled'
            prompt_preview = s.prompt.length > 80 ? "#{s.prompt[0..77]}..." : s.prompt
            "- [#{s.id[0..7]}] #{s.kind}(#{s.expression}) #{status} | " \
              "next: #{s.next_run_at || 'n/a'} | #{prompt_preview}"
          end

          "Scheduled tasks (#{schedules.size}):\n#{lines.join("\n")}"
        end
      end

      # Tool for removing scheduled tasks
      class ScheduleRemove < RubyLLM::Tool
        description 'Remove a scheduled task by its ID (full or partial match)'
        param :id, desc: 'Schedule ID (full UUID or first 8 characters)', required: true

        # @param store [Scheduler::ScheduleStore] shared schedule store
        def initialize(store:)
          super()
          @store = store
        end

        def execute(id:)
          # Support partial ID matching
          schedule = @store.get(id) || @store.list.find { |s| s.id.start_with?(id) }
          return "Schedule not found: #{id}" unless schedule

          @store.remove(schedule.id)
          "Removed schedule #{schedule.id} (#{schedule.kind}: #{schedule.expression})"
        end
      end
    end
  end
end
