# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-03

### Added

- Core agent framework with tool calling support
- Multi-channel support (CLI, Telegram, Discord)
- Provider abstraction for LLM integration
- Session management and conversation history
- Event bus for inter-component communication
- Configuration system with YAML support
- Built-in tools: web search, file operations, code execution
- CLI interface via Thor
- Task scheduling with three schedule kinds: one-shot `at` (ISO 8601), recurring `every` (duration), and `cron` (cron expressions with optional timezone)
- Schedule tools for the LLM: `schedule_add`, `schedule_list`, `schedule_remove`
- Background scheduler service with configurable tick interval
- Response routing to deliver scheduled task results to a target channel
- JSON persistence for schedules at `~/.nanobot/schedules.json`
- `fugit` dependency for cron/duration/timestamp parsing
