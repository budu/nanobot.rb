# Nanobot.rb

[![Ruby](https://img.shields.io/badge/Ruby-4.0%2B-blue)](https://www.ruby-lang.org/)

A minimal, complete personal AI assistant framework. Small enough to read in
an afternoon, functional enough to use every day, clean enough to fork and
build on.

## Overview

Nanobot.rb is a Ruby port of [Nanobot](https://github.com/HKUDS/nanobot) - a personal AI assistant framework designed for
simplicity, privacy, and readability. It provides the essential building blocks of an AI
agent and stops there. Major new features belong in forks, not in this codebase.

- **Multi-provider LLM support** via [RubyLLM](https://rubyllm.com/) - Anthropic, OpenAI, Gemini, DeepSeek, Ollama, OpenRouter, and [many more](https://rubyllm.com/available-models/)
- **Built-in tools** - file operations, shell execution, web search, web fetch
- **Task scheduling** - one-shot reminders, recurring intervals, and cron expressions
- **Six channels** - CLI, Slack, Telegram, Discord, Email, HTTP Gateway
- **Persistent memory** - long-term memory and daily notes across sessions
- **Security-aware** - workspace sandboxing, command filtering, access control

See [docs/goals.md](docs/goals.md) for the project philosophy and
[docs/use-cases.md](docs/use-cases.md) for detailed usage scenarios.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
- [Built-in Tools](#built-in-tools)
- [Workspace Structure](#workspace-structure)
- [Security](#security)
- [Development](#development)
- [Architecture](#architecture)
- [Forking and Extending](#forking-and-extending)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Prerequisites

- Ruby 4.0.1 or higher
- Bundler gem
- An LLM API key (OpenAI, Anthropic, OpenRouter, etc.)

### From Source

```bash
# Clone the repository
git clone https://github.com/nanobot-rb/nanobot.rb
cd nanobot.rb

# Install dependencies
bundle install

# Run tests to verify installation
bundle exec rspec
```

### As a Gem (Coming Soon)

```bash
gem install nanobot
```

## Quick Start

### 1. Initialize Nanobot

```bash
bundle exec bin/nanobot onboard
```

This creates the configuration directory at `~/.nanobot/` with:
- `config.json` - Main configuration file
- `workspace/` - Agent workspace directory
- `sessions/` - Conversation history storage

### 2. Configure API Keys

Edit `~/.nanobot/config.json` and add your API keys:

```json
{
  "providers": {
    "anthropic": {
      "api_key": "sk-ant-api03-..."
    },
    "openai": {
      "api_key": "sk-..."
    },
    "gemini": {
      "api_key": "AIza..."
    },
    "deepseek": {
      "api_key": "sk-..."
    },
    "ollama": {
      "api_base": "http://localhost:11434"
    },
    "openrouter": {
      "api_key": "sk-or-v1-..."
    }
  }
}
```

You only need to configure the providers you plan to use. For the full list
of supported providers and models, see [RubyLLM Available Models](https://rubyllm.com/available-models/).

### 3. Start Chatting

```bash
# Interactive mode
bundle exec bin/nanobot agent

# Single message
bundle exec bin/nanobot agent -m "What's the weather like?"

# With specific model
bundle exec bin/nanobot agent --model openai/gpt-4o-mini -m "Write a haiku"
```

## Configuration

Configuration is stored in `~/.nanobot/config.json`:

```json
{
  "providers": {
    "openrouter": {
      "api_key": "sk-or-v1-...",
      "api_base": "https://openrouter.ai/api/v1"
    },
    "anthropic": {
      "api_key": "sk-ant-..."
    },
    "openai": {
      "api_key": "sk-..."
    }
  },
  "provider": "anthropic",
  "agents": {
    "defaults": {
      "model": "claude-haiku-4-5",
      "workspace": "~/.nanobot/workspace",
      "max_tokens": 4096,
      "temperature": 0.7,
      "max_tool_iterations": 20
    }
  },
  "tools": {
    "web": {
      "search": {
        "api_key": "BRAVE_SEARCH_API_KEY"
      }
    },
    "exec": {
      "timeout": 60
    },
    "restrict_to_workspace": true
  }
}
```

### Configuration Options

| Section            | Key                    | Description                         | Default                  |
|--------------------|------------------------|-------------------------------------|--------------------------|
| `provider  `         |                        | Active provider name                | `anthropic`                |
| `agents.defaults  `  | `model`                  | Default LLM model                   | `claude-haiku-4-5`         |
|                    | `workspace`              | Agent workspace directory           | `~/.nanobot/workspace`     |
|                    | `max_tokens`             | Maximum response tokens             | `4096`                     |
|                    | `temperature`            | LLM temperature (0-1)               | `0.7`                      |
|                    | `max_tool_iterations`    | Max tool execution cycles           | `20`                       |
| `tools`              | `restrict_to_workspace  `| Sandbox file/shell operations       | `true`                     |
| `tools.exec`         | `timeout`                | Command execution timeout (seconds) | `60`                       |
| `scheduler`          | `enabled`                | Enable task scheduling              | `true`                     |
|                    | `tick_interval`          | Seconds between schedule checks     | `15`                       |

## Usage

### Command Line Interface

```bash
# Start interactive agent
bundle exec bin/nanobot agent

# Single message mode
bundle exec bin/nanobot agent -m "Calculate fibonacci(10)"

# Use specific model
bundle exec bin/nanobot agent --model openai/gpt-4o-mini

# Check configuration
bundle exec bin/nanobot status

# Initialize configuration
bundle exec bin/nanobot onboard
```

### Ruby API

```ruby
require 'nanobot'

# Load configuration
config = Nanobot::Config::Loader.load

# Create provider
provider = Nanobot::Providers::RubyLLMProvider.new(
  api_key: config.api_key,
  provider: config.provider,
  default_model: config.agents.defaults.model
)

# Create message bus and agent loop
bus = Nanobot::Bus::MessageBus.new
agent = Nanobot::Agent::Loop.new(
  bus: bus,
  provider: provider,
  workspace: File.expand_path(config.agents.defaults.workspace)
)

# Process a single message directly
response = agent.process_direct("What is 2+2?")
puts response
```

## Built-in Tools

Nanobot uses **RubyLLM-native tools** that inherit from `RubyLLM::Tool` for seamless integration with the LLM provider layer.

### File Operations

- **ReadFile** - Read file contents
  - Supports workspace sandboxing
  - Returns full file content

- **WriteFile** - Create or overwrite files
  - Auto-creates parent directories
  - Workspace sandboxing support

- **EditFile** - Replace text in files
  - Performs exact string replacement
  - Validates single occurrence to avoid ambiguity

- **ListDir** - List directory contents
  - Shows files and directories
  - Workspace sandboxing support

### Shell Execution

- **Exec** - Execute shell commands with safety filters
  - Configurable timeout protection
  - Dangerous command blocking (rm -rf, shutdown, etc.)
  - Optional workspace sandboxing
  - Captures stdout, stderr, and exit code

### Web Tools

- **WebSearch** - Search the web using Brave Search API
  - Requires `BRAVE_SEARCH_API_KEY` environment variable or config
  - Returns formatted search results

- **WebFetch** - Fetch and parse web pages
  - Extracts main content from HTML
  - Removes scripts and styles
  - Returns title, URL, and cleaned text

### Task Scheduling

- **ScheduleAdd** - Create scheduled tasks
  - One-shot `at` (ISO 8601 timestamp): "remind me at 3:30pm"
  - Recurring `every` (duration): "check every 30 minutes"
  - Cron expressions: "every weekday at 9am" (`0 9 * * 1-5`)
  - Optional timezone and delivery target (channel + chat)

- **ScheduleList** - List all scheduled tasks with status and next run time

- **ScheduleRemove** - Remove a scheduled task by full or partial ID

Schedules fire by publishing synthetic messages to the message bus, so the
agent loop processes them like any other message. Results can be routed to a
specific channel (e.g., Slack) via the `deliver_to` option. Schedule tools
are only available in `serve` mode where the background scheduler is running.

### Tool Architecture

Tools inherit from `RubyLLM::Tool` and follow the pattern:

```ruby
class MyTool < RubyLLM::Tool
  description 'Tool description for the LLM'
  param :arg_name, desc: 'Argument description', required: true

  def initialize(**options)
    super()
    @options = options
  end

  def execute(arg_name:)
    # Tool logic here
    "Result"
  end
end
```

The LLM receives properly formatted tool definitions and can call them with structured arguments.

## Workspace Structure

```
~/.nanobot/
├── config.json            # Main configuration
├── sessions/
│   └── *.jsonl            # Conversation history
└── workspace/
    ├── AGENTS.md          # Agent personality and behavior
    ├── SOUL.md            # Core values and principles
    ├── USER.md            # User profile and preferences
    ├── TOOLS.md           # Custom tool documentation
    ├── IDENTITY.md        # Agent identity (name, vibe, emoji, avatar)
    └── memory/
        ├── MEMORY.md      # Long-term persistent memory
        └── YYYY-MM-DD.md  # Daily notes (auto-created)
```

### Bootstrap Files

Bootstrap files in the workspace customize agent behavior:

- **AGENTS.md**: Define agent personality, expertise, and response style
- **SOUL.md**: Core values and ethical guidelines
- **USER.md**: User preferences and context
- **TOOLS.md**: Documentation for custom tools
- **IDENTITY.md**: Agent identity — name, creature type, vibe, emoji, and avatar (see [OpenClaw IDENTITY spec](https://docs.openclaw.ai/reference/templates/IDENTITY))

## Security

### Threat Model

Nanobot.rb is designed as a **personal assistant for trusted environments**. It
is adequate for single-user, self-hosted use with proper configuration. It is
**not hardened for multi-tenant or adversarial deployments**. If you expose
channels to untrusted users, additional hardening is required — configure
`allow_from` whitelists, enable workspace sandboxing, and add tool confirmation
callbacks.

### Workspace Sandboxing

File and shell operations are sandboxed to the workspace directory by default
(`restrict_to_workspace: true`). This prevents the agent from accessing or
modifying files outside its workspace. The sandbox resolves symlinks to block
escape attempts. Set `restrict_to_workspace: false` only if you understand the
risk and trust the agent with full filesystem access.

### Command Filtering

The shell tool blocks common dangerous patterns (`rm -rf`, `shutdown`, `dd`,
fork bombs, etc.) via a denylist. **This is not a true security boundary** — an
LLM or attacker can bypass it through nested shells, alternative commands, or
encoding tricks. It prevents accidents, not attacks. For strong isolation, use
OS-level sandboxing (containers, seccomp, etc.).

### Access Control

- Channel-level user whitelisting via `allow_from`
- Empty `allow_from` **allows all users** (a warning is logged)
- Non-empty `allow_from` restricts to specified users only
- For channels exposed to untrusted networks, always configure explicit
  whitelists

### SSRF Protection

The web fetch tool validates URLs and blocks requests to private IP ranges
(127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, link-local, and
IPv6 equivalents). Redirects are re-validated at each hop. Responses are
capped at 1 MB.

### Credential Storage

API keys and tokens are stored as **plaintext JSON** in `~/.nanobot/config.json`
with `0600` file permissions. Session files are similarly protected. There is no
encryption at rest — if your machine is compromised, credentials are exposed.
Protect your `~/.nanobot/` directory accordingly.

## Development

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run with coverage report
bundle exec rspec

# Run specific test file
bundle exec rspec spec/agent/loop_spec.rb
```

Run `bundle exec rspec` to see current test coverage.

### Code Style

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A
```

### Project Structure

```
lib/nanobot/
├── agent/
│   ├── loop.rb              # Core agent processing loop
│   ├── context.rb           # System prompt builder
│   ├── memory.rb            # Memory management
│   └── tools/
│       ├── filesystem.rb    # File operations (read, write, edit, list)
│       ├── schedule.rb      # Task scheduling (add, list, remove)
│       ├── shell.rb         # Shell execution with safety filters
│       └── web.rb           # Web search and fetch
├── bus/
│   ├── events.rb            # Event definitions
│   └── message_bus.rb       # Message routing
├── channels/
│   ├── base.rb              # Channel interface
│   ├── manager.rb           # Channel orchestration
│   ├── slack.rb             # Slack integration
│   ├── telegram.rb          # Telegram integration
│   ├── discord.rb           # Discord integration
│   ├── email.rb             # Email (IMAP/SMTP) integration
│   └── gateway.rb           # HTTP Gateway
├── cli/
│   └── commands.rb          # CLI implementation
├── config/
│   ├── schema.rb            # Configuration schema
│   └── loader.rb            # Config loading/validation
├── providers/
│   ├── base.rb              # Provider interface
│   └── rubyllm_provider.rb  # RubyLLM integration
├── scheduler/
│   ├── store.rb             # Schedule CRUD and JSON persistence
│   └── service.rb           # Background tick thread, fires due jobs
├── session/
│   └── manager.rb           # Session persistence
└── version.rb               # Version constant
```

## Architecture

### Message Flow

```
User Input → Channel → Message Bus → Agent Loop → LLM Provider
                            ↓              ↓
                     Session Manager   Tool System
                            ↓              ↓
                      JSONL Storage   Tool Execution
```

### Core Components

- **Message Bus**: Queue-based message routing with pub/sub pattern
- **Agent Loop**: Tool-calling loop with LLM integration
- **Tool System**: RubyLLM-based tools directly instantiated by the agent
- **Session Manager**: JSONL-based conversation persistence
- **Context Builder**: System prompt assembly from bootstrap files
- **Memory Store**: Long-term and daily memory management

## Forking and Extending

Nanobot.rb is designed to be forked. The architecture is modular so you can
add tools, channels, providers, or entirely new capabilities without fighting
the codebase.

### Adding Tools

Tools inherit from `RubyLLM::Tool`:

```ruby
class WeatherTool < RubyLLM::Tool
  description 'Get current weather for a location'
  param :location, desc: 'City name or coordinates', required: true

  def execute(location:)
    "Weather in #{location}: Sunny, 72F"
  end
end
```

### Adding Channels

Channels extend `Nanobot::Channels::BaseChannel` and implement `start`,
`stop`, and `send`.

See [docs/goals.md](docs/goals.md) for what belongs in a fork vs. this repo.

## Contributing

Contributions that improve what exists are welcome - bug fixes, test coverage,
documentation, security hardening, and code clarity. See
[CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

New features that expand the scope (streaming, MCP, RAG, multi-agent, etc.)
belong in a fork. The architecture is designed to support this.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

This is a Ruby port of the original [Nanobot](https://github.com/HKUDS/nanobot) Python project by the [Data Intelligence Lab at the University of Hong Kong (HKUDS)](https://github.com/HKUDS). All credit for the original design and architecture goes to them.

Multi-provider LLM support is powered by [RubyLLM](https://rubyllm.com/) by [Carmine Paolino](https://github.com/crmne).

## Support

- **Issues**: [GitHub Issues](https://github.com/nanobot-rb/nanobot.rb/issues)
- **Discussions**: [GitHub Discussions](https://github.com/nanobot-rb/nanobot.rb/discussions)
- **Goals**: [docs/goals.md](docs/goals.md)
- **Use Cases**: [docs/use-cases.md](docs/use-cases.md)
