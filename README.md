# Nanobot.rb

[![Ruby](https://img.shields.io/badge/Ruby-4.0%2B-blue)](https://www.ruby-lang.org/)

A Ruby port of [Nanobot](https://github.com/nanobot-ai/nanobot) - a lightweight, modular personal AI assistant framework designed for simplicity, extensibility, and security.

## Overview

Nanobot.rb is a clean, modular AI agent framework that provides a foundation for building intelligent assistants with:

- 🤖 **Multi-provider LLM support** via RubyLLM (OpenAI, Anthropic, OpenRouter, Groq, etc.)
- 🔧 **Extensible tool system** with built-in file, shell, and web capabilities
- 💬 **Multi-channel communication** architecture (extensible for Telegram, Discord, etc.)
- 💾 **Persistent memory** and conversation session management
- 🛡️ **Security-first design** with workspace sandboxing and command filtering

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
    }
  }
}
```

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
    "restrict_to_workspace": false
  }
}
```

### Configuration Options

| Section            | Key                    | Description                         | Default                  |
|--------------------|------------------------|-------------------------------------|--------------------------|
| `provider`         |                        | Active provider name                | `anthropic`              |
| `agents.defaults`  | `model`                | Default LLM model                   | `claude-haiku-4-5`       |
|                    | `workspace`            | Agent workspace directory           | `~/.nanobot/workspace`   |
|                    | `max_tokens`           | Maximum response tokens             | `4096`                   |
|                    | `temperature`          | LLM temperature (0-1)               | `0.7`                    |
|                    | `max_tool_iterations`  | Max tool execution cycles           | `20`                     |
| `tools`            | `restrict_to_workspace`| Sandbox file/shell operations       | `false`                  |
| `tools.exec`       | `timeout`              | Command execution timeout (seconds) | `60`                     |

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

### Access Control

- Channel-level user whitelisting via `allow_from` (for custom channel implementations)
- Empty whitelist allows all users
- Non-empty whitelist restricts to specified users

### Command Filtering

The shell execution tool blocks dangerous patterns:
- Destructive operations (`rm -rf`, `format`, `dd`)
- System operations (`shutdown`, `reboot`)
- Fork bombs and recursive commands
- Direct disk device access

### Workspace Sandboxing

Enable `restrict_to_workspace: true` to:
- Limit all file operations to workspace directory
- Prevent access to system files
- Isolate agent operations

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
│       ├── filesystem.rb    # File operations
│       ├── shell.rb         # Shell execution
│       └── web.rb           # Web tools
├── bus/
│   ├── events.rb            # Event definitions
│   └── message_bus.rb       # Message routing
├── channels/
│   ├── base.rb              # Channel interface
│   └── manager.rb           # Channel orchestration
├── config/
│   ├── schema.rb            # Configuration schema
│   └── loader.rb            # Config loading/validation
├── providers/
│   ├── base.rb              # Provider interface
│   └── rubyllm_provider.rb  # RubyLLM integration
├── session/
│   └── manager.rb           # Session persistence
└── cli/
    └── commands.rb          # CLI implementation
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

### Extending Nanobot

#### Creating Custom Tools

```ruby
class WeatherTool < RubyLLM::Tool
  description 'Get current weather for a location'
  param :location, desc: 'City name or coordinates', required: true

  def execute(location:)
    # Your implementation here
    "Weather in #{location}: Sunny, 72F"
  end
end
```

Custom tools are `RubyLLM::Tool` instances passed directly to the agent loop.

#### Creating Custom Channels

```ruby
class SlackChannel < Nanobot::Channels::BaseChannel
  def start
    @client = Slack::Client.new(token: @config['token'])

    @client.on(:message) do |message|
      handle_message(
        sender_id: message.user,
        chat_id: message.channel,
        content: message.text
      )
    end

    @client.start!
  end

  def stop
    @client&.stop
  end

  def send(message)
    @client.post_message(
      channel: message.chat_id,
      text: message.content
    )
  end
end
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Areas for Contribution

- Channel implementations (Telegram, Discord, Slack, etc.) using the `BaseChannel` interface
- New tool development
- Performance optimizations
- Documentation improvements
- Bug fixes and test coverage

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

This is a Ruby port of the original [Nanobot](https://github.com/nanobot-ai/nanobot) Python project by the Nanobot team. All credit for the original design and architecture goes to them.

## Support

- **Issues**: [GitHub Issues](https://github.com/nanobot-rb/nanobot.rb/issues)
- **Discussions**: [GitHub Discussions](https://github.com/nanobot-rb/nanobot.rb/discussions)
- **Documentation**: [docs/](docs/) directory
