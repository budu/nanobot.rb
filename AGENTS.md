# Nanobot Agents Documentation

## Overview

Nanobot agents are AI-powered assistants that process messages, execute tools, and maintain conversations. This document covers agent architecture, configuration, customization, and best practices.

## Table of Contents

- [Agent Architecture](#agent-architecture)
- [Core Components](#core-components)
- [Agent Lifecycle](#agent-lifecycle)
- [Tool System](#tool-system)
- [Memory System](#memory-system)
- [Customization](#customization)
- [Bootstrap Files](#bootstrap-files)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Agent Architecture

### Processing Loop

The agent operates in a continuous loop:

```
1. Receive Message
2. Build Context (System Prompt + History)
3. Send to LLM Provider
4. Parse Response for Tool Calls
5. Execute Tools
6. Loop back with results or return response
```

### Key Classes

- **`Nanobot::Agent::Loop`** - Main agent processing engine
- **`Nanobot::Agent::ContextBuilder`** - System prompt construction
- **`Nanobot::Agent::MemoryStore`** - Memory management
- **`Nanobot::Agent::Tools::Registry`** - Tool registration and execution

## Core Components

### Agent Loop

The agent loop (`lib/nanobot/agent/loop.rb`) is the heart of the system:

```ruby
class Loop
  def initialize(
    provider:,           # LLM provider instance
    config:,            # Configuration hash
    tools: nil,         # Tool registry
    session: nil,       # Session manager
    exec_config: nil,   # Execution config
    restrict_to_workspace: false
  )

  def process_message(message)
    # Main processing logic
  end

  def process_direct(content, channel: nil, chat_id: nil)
    # Direct message processing
  end
end
```

### Context Builder

The context builder assembles system prompts from multiple sources:

```ruby
class ContextBuilder
  def build_system_prompt
    # Combines:
    # - Runtime information (date, workspace)
    # - Bootstrap files (AGENTS.md, SOUL.md, etc.)
    # - Memory context
  end

  def build_messages(message, history = [], channel = nil)
    # Constructs message array for LLM
  end
end
```

### Memory Store

Long-term and daily memory management:

```ruby
class MemoryStore
  def initialize(workspace_dir)

  def get_memory_context
    # Returns formatted memory for context
  end

  def add_memory(content)
    # Adds to long-term memory
  end

  def add_daily_note(content)
    # Adds to today's notes
  end
end
```

## Agent Lifecycle

### 1. Initialization

```ruby
# Load configuration
config = Nanobot::Config::Loader.new.load

# Create provider
provider = Nanobot::Providers::RubyLLMProvider.new(config: config)

# Initialize agent
agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  restrict_to_workspace: true  # Optional sandboxing
)
```

### 2. Message Processing

```ruby
# Process a message
response = agent.process_message(
  Nanobot::Bus::InboundMessage.new(
    content: "What's the weather?",
    channel: "cli",
    chat_id: "user123",
    from_user: "alice"
  )
)
```

### 3. Tool Execution

The agent automatically:
1. Detects tool calls in LLM responses
2. Validates parameters against schemas
3. Executes tools safely
4. Returns results to LLM
5. Continues until completion

### 4. Session Management

Sessions are automatically saved as JSONL files:
```
~/.nanobot/workspace/sessions/main.jsonl
~/.nanobot/workspace/sessions/channel_chatid.jsonl
```

## Tool System

### Built-in Tools

| Tool | Name | Description |
|------|------|-------------|
| **File Operations** | | |
| | `read_file` | Read file contents |
| | `write_file` | Create/overwrite files |
| | `edit_file` | Replace text in files |
| | `list_dir` | List directory contents |
| **Shell** | | |
| | `exec` | Execute shell commands |
| **Web** | | |
| | `web_search` | Search the web (requires Brave API) |
| | `web_fetch` | Fetch and parse web pages |
| **Communication** | | |
| | `message` | Send messages to channels |

### Creating Custom Tools

```ruby
class CustomTool < Nanobot::Agent::Tools::Tool
  def name
    'custom_tool'
  end

  def description
    'Does something custom'
  end

  def parameters
    {
      'type' => 'object',
      'properties' => {
        'input' => {
          'type' => 'string',
          'description' => 'Input parameter'
        }
      },
      'required' => ['input']
    }
  end

  def execute(input:)
    # Tool implementation
    "Processed: #{input}"
  end
end
```

### Tool Registration

```ruby
# During agent initialization
tools = Nanobot::Agent::Tools::Registry.new(workspace_dir: workspace)

# Register custom tool
tools.register(CustomTool.new)

# Pass to agent
agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  tools: tools
)
```

### Tool Security

Tools implement several security measures:

- **Parameter validation** against JSON schemas
- **Command filtering** for dangerous operations
- **Timeout protection** for long-running commands
- **Workspace sandboxing** when enabled
- **Error handling** with graceful failures

## Memory System

### Memory Types

1. **Long-term Memory** (`memory/MEMORY.md`)
   - Persistent across all sessions
   - Manually curated important information
   - Loaded at agent startup

2. **Daily Notes** (`memory/YYYY-MM-DD.md`)
   - Auto-created each day
   - Session-specific observations
   - Included in context for current day

3. **Session History** (`sessions/*.jsonl`)
   - Complete conversation logs
   - Tool executions and results
   - Used for conversation continuity

### Memory Management

```ruby
# Access memory store
memory = Nanobot::Agent::MemoryStore.new(workspace)

# Add to long-term memory
memory.add_memory("User prefers dark mode interfaces")

# Add daily note
memory.add_daily_note("Helped user debug Ruby code")

# Get formatted context
context = memory.get_memory_context
```

## Customization

### Bootstrap Files

Bootstrap files in the workspace customize agent behavior:

#### AGENTS.md

Defines agent personality and expertise:

```markdown
# Agent Configuration

You are a helpful AI assistant specialized in Ruby development.

## Expertise
- Ruby programming and best practices
- Rails framework
- Testing with RSpec
- Code review and refactoring

## Communication Style
- Clear and concise explanations
- Use code examples when helpful
- Ask clarifying questions when needed
```

#### SOUL.md

Core values and principles:

```markdown
# Core Values

- Always prioritize user safety and security
- Respect user privacy and confidentiality
- Provide accurate, helpful information
- Admit limitations and uncertainties
- Refuse harmful or unethical requests
```

#### USER.md

User preferences and context:

```markdown
# User Profile

- Name: Alice
- Expertise: Intermediate Ruby developer
- Preferences:
  - Prefers functional programming style
  - Uses VS Code editor
  - Likes detailed explanations
```

#### TOOLS.md

Custom tool documentation:

```markdown
# Custom Tools

## project_search
Search the current project for code patterns

## deploy
Deploy application to staging/production
```

### Configuration Options

```json
{
  "agents": {
    "defaults": {
      "model": "gpt-4",
      "temperature": 0.7,
      "max_tokens": 4096,
      "max_tool_iterations": 20,
      "workspace": "~/.nanobot/workspace"
    },
    "custom_agent": {
      "model": "claude-3-opus",
      "temperature": 0.5,
      "system_prompt": "You are a code review expert..."
    }
  }
}
```

## Examples

### Basic Agent Usage

```ruby
require 'nanobot'

# Initialize with defaults
config = Nanobot::Config::Loader.new.load
provider = Nanobot::Providers::RubyLLMProvider.new(config: config)
agent = Nanobot::Agent::Loop.new(provider: provider, config: config)

# Process a message
response = agent.process_direct("Write a Ruby function to calculate fibonacci")
puts response
```

### Agent with Custom Tools

```ruby
# Create custom tool
class GitTool < Nanobot::Agent::Tools::Tool
  def name; 'git_status'; end
  def description; 'Get git repository status'; end
  def parameters
    { 'type' => 'object', 'properties' => {} }
  end
  def execute
    `git status`
  end
end

# Register and use
tools = Nanobot::Agent::Tools::Registry.new
tools.register(GitTool.new)

agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  tools: tools
)
```

### Multi-Channel Agent

```ruby
# Initialize message bus
bus = Nanobot::Bus::MessageBus.new

# Create channel manager
manager = Nanobot::Channels::Manager.new(config: config, bus: bus)

# Add channels
telegram = Nanobot::Channels::TelegramChannel.new(config: config['channels']['telegram'])
manager.add_channel(telegram)

# Start agent with bus
agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  bus: bus
)

# Start all channels
manager.start_all
```

### Restricted Agent

```ruby
# Create sandboxed agent
agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  restrict_to_workspace: true,  # Sandbox file operations
  exec_config: {
    timeout: 30,                # 30 second timeout
    allowed_commands: ['ls', 'cat', 'grep']  # Whitelist commands
  }
)
```

## Best Practices

### 1. Security

- **Always validate** user inputs before processing
- **Enable sandboxing** for untrusted environments
- **Use timeouts** for tool executions
- **Filter dangerous** commands and operations
- **Implement rate limiting** for API calls

### 2. Performance

- **Cache provider instances** - Don't recreate for each message
- **Reuse tool registries** - Initialize once and share
- **Batch operations** when possible
- **Set reasonable timeouts** for tools
- **Monitor memory usage** in long-running agents

### 3. Reliability

- **Handle errors gracefully** - Don't crash on tool failures
- **Implement retries** for transient failures
- **Log important events** for debugging
- **Save session state** frequently
- **Validate configurations** at startup

### 4. User Experience

- **Provide clear feedback** during long operations
- **Stream responses** when possible
- **Handle interruptions** gracefully
- **Maintain conversation context** across sessions
- **Personalize responses** using bootstrap files

### 5. Development

- **Write comprehensive tests** for custom tools
- **Document tool parameters** clearly
- **Use semantic versioning** for changes
- **Follow Ruby style guides** (RuboCop)
- **Keep tools focused** on single responsibilities

## Troubleshooting

### Common Issues

1. **Agent not responding**
   - Check LLM provider configuration
   - Verify API keys are valid
   - Check network connectivity
   - Review logs for errors

2. **Tools not executing**
   - Verify tool registration
   - Check parameter validation
   - Review tool permissions
   - Check workspace restrictions

3. **Memory not persisting**
   - Verify workspace directory exists
   - Check file permissions
   - Review memory file format
   - Ensure proper session management

4. **High token usage**
   - Reduce max_tool_iterations
   - Optimize system prompts
   - Clear old session history
   - Use more efficient models

### Debug Mode

Enable debug logging:

```ruby
agent = Nanobot::Agent::Loop.new(
  provider: provider,
  config: config,
  logger: Logger.new(STDOUT, level: Logger::DEBUG)
)
```

## Advanced Topics

### Custom Providers

Implement the provider interface:

```ruby
class CustomProvider < Nanobot::Providers::Base
  def complete(messages, tools: nil)
    # Custom LLM integration
  end

  def models
    ['custom-model-1', 'custom-model-2']
  end
end
```

### Tool Composition

Chain tools together:

```ruby
class ComposedTool < Nanobot::Agent::Tools::Tool
  def initialize(tool1, tool2)
    @tool1 = tool1
    @tool2 = tool2
  end

  def execute(**params)
    result1 = @tool1.execute(**params)
    @tool2.execute(input: result1)
  end
end
```

### Agent Coordination

Run multiple specialized agents:

```ruby
# Code review agent
reviewer = Nanobot::Agent::Loop.new(
  provider: provider,
  config: review_config
)

# Documentation agent
documenter = Nanobot::Agent::Loop.new(
  provider: provider,
  config: doc_config
)

# Coordinate agents
code = "def hello; puts 'world'; end"
review = reviewer.process_direct("Review this code: #{code}")
docs = documenter.process_direct("Document this code: #{code}")
```

## Future Enhancements

### Planned Features

- **Plugin system** for dynamic tool loading
- **Agent templates** for common use cases
- **Streaming responses** for real-time feedback
- **Multi-modal support** for images/audio
- **Agent collaboration** protocols
- **Fine-tuning support** for custom models
- **Observability tools** for monitoring

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to agent development.

## References

- [Architecture Documentation](docs/bootstrap/nanobot_detailed_architecture.md)
- [Implementation Guide](docs/bootstrap/ruby_port_implementation_guide.md)
- [Tool Development Guide](docs/bootstrap/quick_reference.md)
- [Original Python Nanobot](https://github.com/nanobot-ai/nanobot)
