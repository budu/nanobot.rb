# Nanobot Ruby Port - Implementation Guide

This document provides a roadmap and recommendations for porting Nanobot from Python to Ruby.

---

## 1. Project Overview for Ruby Port

### What You're Building
A lightweight AI agent framework in Ruby with:
- Multi-provider LLM support (OpenRouter, Anthropic, OpenAI, etc.)
- Multi-channel chat integration (Telegram, Discord, WhatsApp, Feishu)
- Tool-calling agent loop with function execution
- Persistent conversation memory and sessions
- Scheduled tasks and background job support
- Extensible skill system

### Target Ruby Version
- Ruby 3.0+
- Recommended: Ruby 3.2+

### Estimated Scope
- ~4,000-5,000 lines of Ruby code
- ~40-50 Ruby files
- ~25-30 external gem dependencies

---

## 2. Core Architecture Overview (Ruby)

```
┌─────────────────────────────────────────┐
│      Chat Channels                      │
│  (Telegram, Discord, WhatsApp, etc)    │
└──────────────────┬──────────────────────┘
                   │
              Message Bus
         (Queue-based, Threadsafe)
                   │
      ┌────────────┴────────────┐
      ↓                         ↓
  Agent Loop                Configuration
  (Main Loop)                (YAML/JSON)
      │
  ├─ Context Builder
  ├─ Tool Registry
  ├─ Tool Execution
  ├─ Session Manager
  ├─ Memory Store
  └─ LLM Provider
```

---

## 3. Technology Stack Recommendations

### Core Framework
```gemfile
# CLI & Commands
gem 'thor'                              # CLI framework (instead of Typer)

# HTTP & Network
gem 'faraday'                           # HTTP client
gem 'faraday-multipart'                 # Multipart support
gem 'websocket-eventmachine'            # WebSocket support

# Data Validation & Config
gem 'dry-types'                         # Type system
gem 'dry-struct'                        # Immutable objects
gem 'dry-validation'                    # Schema validation
gem 'dry-configurable'                  # Configuration DSL

# JSON & Serialization
gem 'json'                              # JSON handling (stdlib)
gem 'json-schema'                       # JSON schema validation

# Async & Concurrency
gem 'concurrent-ruby'                   # Thread utilities
gem 'fiber'                             # Or use async gem

# Logging
gem 'logger'                            # Stdlib logger
gem 'log4r'                             # More advanced logging (optional)

# Date/Time
gem 'time'                              # Stdlib (Ruby 3.0+)
gem 'tzinfo'                            # Timezone support

# File & Path
gem 'pathname'                          # Stdlib path handling

# Cron & Scheduling
gem 'rufus-scheduler'                   # Cron-like scheduling
gem 'croniter'                          # Cron expression parsing

# LLM & AI
gem 'ruby-openai'                       # OpenAI client (can adapt for other providers)
# Or use direct HTTP via Faraday for multi-provider support

# Chat Channel Libraries
gem 'telegram-bot-ruby'                 # Telegram
gem 'discordrb'                         # Discord
gem 'whatsapp-sdk'                      # WhatsApp
gem 'lark'                              # Feishu/Lark (may need to create)

# Development
gem 'rspec'                             # Testing
gem 'rspec-rails'
gem 'pry'                               # Debugging
gem 'pry-byebug'
gem 'rubocop'                           # Linting
gem 'prettier'                          # Code formatting

# Testing
gem 'webmock'                           # HTTP mocking
gem 'timecop'                           # Time mocking
```

---

## 4. Module Structure (Ruby)

### Recommended Directory Layout

```
nanobot.rb/
├── lib/
│   └── nanobot/
│       ├── agent/
│       │   ├── loop.rb              # Core agent loop
│       │   ├── context.rb           # Prompt building
│       │   ├── memory.rb            # Memory system
│       │   ├── skills.rb            # Skills loader
│       │   ├── subagent.rb          # Background tasks
│       │   └── tools/
│       │       ├── base.rb          # Tool ABC
│       │       ├── registry.rb      # Tool registry
│       │       ├── filesystem.rb    # File operations
│       │       ├── shell.rb         # Shell execution
│       │       ├── web.rb           # Web tools
│       │       ├── message.rb       # Message tool
│       │       ├── spawn.rb         # Spawn subagents
│       │       └── cron.rb          # Cron tool
│       ├── bus/
│       │   ├── message_bus.rb       # Queue system
│       │   └── events.rb            # Event classes
│       ├── channels/
│       │   ├── base.rb              # Base channel
│       │   ├── telegram.rb          # Telegram
│       │   ├── discord.rb           # Discord
│       │   ├── whatsapp.rb          # WhatsApp
│       │   ├── feishu.rb            # Feishu
│       │   └── manager.rb           # Channel manager
│       ├── providers/
│       │   ├── base.rb              # Provider ABC
│       │   └── litellm_provider.rb  # Multi-provider
│       ├── session/
│       │   └── manager.rb           # Session management
│       ├── config/
│       │   ├── schema.rb            # Config schemas
│       │   └── loader.rb            # Config loading
│       ├── cron/
│       │   ├── service.rb           # Cron service
│       │   └── types.rb             # Cron types
│       ├── heartbeat/
│       │   └── service.rb           # Heartbeat
│       ├── cli/
│       │   └── commands.rb          # CLI commands
│       ├── utils/
│       │   └── helpers.rb           # Utility functions
│       └── version.rb               # Version info
├── bin/
│   └── nanobot                       # CLI entry point
├── spec/
│   ├── unit/
│   │   ├── agent/
│   │   ├── tools/
│   │   ├── channels/
│   │   └── ...
│   ├── integration/
│   └── fixtures/
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── README.md
└── nanobot.gemspec
```

---

## 5. Key Implementation Components

### 5.1 Message Bus (Thread-Safe Queue)

```ruby
# lib/nanobot/bus/events.rb
InboundMessage = Struct.new(
  :channel,
  :sender_id,
  :chat_id,
  :content,
  :timestamp,
  :media,
  :metadata,
  keyword_init: true
) do
  def session_key
    "#{channel}:#{chat_id}"
  end
end

OutboundMessage = Struct.new(
  :channel,
  :chat_id,
  :content,
  :reply_to,
  :media,
  :metadata,
  keyword_init: true
)

# lib/nanobot/bus/message_bus.rb
class Nanobot::Bus::MessageBus
  def initialize
    @inbound_queue = Queue.new
    @outbound_queue = Queue.new
    @outbound_subscribers = Hash.new { |h, k| h[k] = [] }
    @running = false
  end

  def publish_inbound(msg)
    @inbound_queue.push(msg)
  end

  def consume_inbound(timeout: nil)
    if timeout
      begin
        @inbound_queue.pop(true)
      rescue ThreadError
        nil
      end
    else
      @inbound_queue.pop
    end
  end

  def publish_outbound(msg)
    @outbound_queue.push(msg)
  end

  def subscribe_outbound(channel, callback)
    @outbound_subscribers[channel] << callback
  end

  def dispatch_outbound
    Thread.new do
      @running = true
      loop do
        msg = @outbound_queue.pop
        break unless msg

        subscribers = @outbound_subscribers[msg.channel]
        subscribers.each do |cb|
          begin
            cb.call(msg)
          rescue => e
            puts "Error dispatching to #{msg.channel}: #{e.message}"
          end
        end
      end
    end
  end

  def stop
    @running = false
  end
end
```

### 5.2 Tool Base Class & Registry

```ruby
# lib/nanobot/agent/tools/base.rb
module Nanobot::Agent::Tools
  class Tool
    TYPE_MAP = {
      "string" => String,
      "integer" => Integer,
      "number" => [Integer, Float],
      "boolean" => [TrueClass, FalseClass],
      "array" => Array,
      "object" => Hash
    }

    def name
      raise NotImplementedError
    end

    def description
      raise NotImplementedError
    end

    def parameters
      raise NotImplementedError
    end

    def execute(**kwargs)
      raise NotImplementedError
    end

    def to_schema
      {
        type: "function",
        function: {
          name: name,
          description: description,
          parameters: parameters
        }
      }
    end

    def validate_params(params)
      errors = []
      schema = parameters || {}

      # Basic validation logic
      errors.concat(_validate(params, schema))
      errors
    end

    private

    def _validate(val, schema, path = "")
      errors = []
      t = schema["type"]

      # Type checking
      if t && TYPE_MAP[t] && !_is_type?(val, TYPE_MAP[t])
        errors << "#{path || 'parameter'} should be #{t}"
      end

      # Enum checking
      if schema["enum"] && !schema["enum"].include?(val)
        errors << "#{path || 'parameter'} must be one of #{schema['enum']}"
      end

      # Required fields for objects
      if t == "object"
        required = schema["required"] || []
        required.each do |field|
          errors << "missing required #{field}" unless val.has_key?(field)
        end

        # Recursive validation for properties
        (schema["properties"] || {}).each do |key, prop_schema|
          if val.has_key?(key)
            new_path = path.empty? ? key : "#{path}.#{key}"
            errors.concat(_validate(val[key], prop_schema, new_path))
          end
        end
      end

      errors
    end

    def _is_type?(val, type)
      type.is_a?(Array) ? type.any? { |t| val.is_a?(t) } : val.is_a?(type)
    end
  end
end

# lib/nanobot/agent/tools/registry.rb
class Nanobot::Agent::Tools::Registry
  def initialize
    @tools = {}
  end

  def register(tool)
    @tools[tool.name] = tool
  end

  def unregister(name)
    @tools.delete(name)
  end

  def get(name)
    @tools[name]
  end

  def has?(name)
    @tools.has_key?(name)
  end

  def get_definitions
    @tools.values.map(&:to_schema)
  end

  def execute(name, params)
    tool = @tools[name]
    return "Error: Tool '#{name}' not found" unless tool

    begin
      errors = tool.validate_params(params)
      return "Error: Invalid parameters for '#{name}': #{errors.join('; ')}" if errors.any?

      tool.execute(**params)
    rescue => e
      "Error executing #{name}: #{e.message}"
    end
  end

  def tool_names
    @tools.keys
  end
end
```

### 5.3 Agent Loop (Core Engine)

```ruby
# lib/nanobot/agent/loop.rb
class Nanobot::Agent::Loop
  def initialize(
    bus:,
    provider:,
    workspace:,
    model: nil,
    max_iterations: 20,
    brave_api_key: nil,
    exec_config: nil,
    cron_service: nil,
    restrict_to_workspace: false
  )
    @bus = bus
    @provider = provider
    @workspace = Pathname.new(workspace)
    @model = model || provider.get_default_model
    @max_iterations = max_iterations
    @brave_api_key = brave_api_key
    @exec_config = exec_config || {}
    @cron_service = cron_service
    @restrict_to_workspace = restrict_to_workspace

    @context = Nanobot::Agent::Context.new(@workspace)
    @sessions = Nanobot::Session::Manager.new(@workspace)
    @tools = Nanobot::Agent::Tools::Registry.new
    @running = false

    _register_default_tools
  end

  def run
    @running = true
    logger.info "Agent loop started"

    loop do
      break unless @running

      msg = @bus.consume_inbound(timeout: 1)
      next unless msg

      begin
        response = process_message(msg)
        @bus.publish_outbound(response) if response
      rescue => e
        logger.error "Error processing message: #{e.message}"
        @bus.publish_outbound(
          OutboundMessage.new(
            channel: msg.channel,
            chat_id: msg.chat_id,
            content: "Sorry, I encountered an error: #{e.message}"
          )
        )
      end
    end
  end

  def stop
    @running = false
    logger.info "Agent loop stopping"
  end

  def process_message(msg)
    # Get or create session
    session = @sessions.get_or_create(msg.session_key)

    # Build context
    messages = @context.build_messages(
      history: session.get_history,
      current_message: msg.content,
      channel: msg.channel,
      chat_id: msg.chat_id
    )

    # Agent loop
    final_content = nil
    iteration = 0

    while iteration < @max_iterations
      iteration += 1

      # Call LLM
      response = @provider.chat(
        messages: messages,
        tools: @tools.get_definitions,
        model: @model
      )

      if response.tool_calls.any?
        # Add assistant message with tool calls
        messages << {
          role: "assistant",
          content: response.content,
          tool_calls: response.tool_calls.map { |tc|
            {
              id: tc.id,
              type: "function",
              function: {
                name: tc.name,
                arguments: JSON.generate(tc.arguments)
              }
            }
          }
        }

        # Execute tools
        response.tool_calls.each do |tool_call|
          result = @tools.execute(tool_call.name, tool_call.arguments)
          messages << {
            role: "tool",
            tool_call_id: tool_call.id,
            name: tool_call.name,
            content: result
          }
        end
      else
        # No tool calls - done
        final_content = response.content
        break
      end
    end

    final_content ||= "I've completed processing but have no response to give."

    # Save to session
    session.add_message("user", msg.content)
    session.add_message("assistant", final_content)
    @sessions.save(session)

    # Return response
    OutboundMessage.new(
      channel: msg.channel,
      chat_id: msg.chat_id,
      content: final_content
    )
  end

  private

  def _register_default_tools
    allowed_dir = @restrict_to_workspace ? @workspace : nil

    @tools.register(Nanobot::Agent::Tools::ReadFileTool.new(allowed_dir: allowed_dir))
    @tools.register(Nanobot::Agent::Tools::WriteFileTool.new(allowed_dir: allowed_dir))
    @tools.register(Nanobot::Agent::Tools::EditFileTool.new(allowed_dir: allowed_dir))
    @tools.register(Nanobot::Agent::Tools::ListDirTool.new(allowed_dir: allowed_dir))
    @tools.register(Nanobot::Agent::Tools::ExecTool.new(
      working_dir: @workspace.to_s,
      timeout: @exec_config[:timeout] || 60,
      restrict_to_workspace: @restrict_to_workspace
    ))
    @tools.register(Nanobot::Agent::Tools::WebSearchTool.new(api_key: @brave_api_key))
    @tools.register(Nanobot::Agent::Tools::WebFetchTool.new)
  end

  def logger
    @logger ||= Logger.new($stdout)
  end
end
```

### 5.4 Session Manager (JSONL-based)

```ruby
# lib/nanobot/session/manager.rb
class Nanobot::Session::Manager
  Message = Struct.new(:role, :content, :timestamp, keyword_init: true)

  class Session
    attr_accessor :key, :messages, :created_at, :updated_at, :metadata

    def initialize(key, messages: [], created_at: nil, updated_at: nil, metadata: {})
      @key = key
      @messages = messages
      @created_at = created_at || Time.now
      @updated_at = updated_at || Time.now
      @metadata = metadata
    end

    def add_message(role, content)
      @messages << {
        role: role,
        content: content,
        timestamp: Time.now.iso8601
      }
      @updated_at = Time.now
    end

    def get_history(max_messages: 50)
      recent = @messages.length > max_messages ? @messages[-max_messages..-1] : @messages
      recent.map { |m| { role: m[:role], content: m[:content] } }
    end

    def clear
      @messages = []
      @updated_at = Time.now
    end
  end

  def initialize(workspace)
    @workspace = Pathname.new(workspace)
    @sessions_dir = Pathname.new(File.expand_path("~/.nanobot/sessions"))
    @sessions_dir.mkpath unless @sessions_dir.exist?
    @cache = {}
  end

  def get_or_create(key)
    return @cache[key] if @cache[key]

    session = _load(key) || Session.new(key)
    @cache[key] = session
    session
  end

  def save(session)
    path = @sessions_dir / "#{_safe_filename(session.key)}.jsonl"

    File.open(path, "w") do |f|
      # Metadata line
      metadata_line = {
        _type: "metadata",
        created_at: session.created_at.iso8601,
        updated_at: session.updated_at.iso8601,
        metadata: session.metadata
      }
      f.puts(JSON.generate(metadata_line))

      # Message lines
      session.messages.each do |msg|
        f.puts(JSON.generate(msg))
      end
    end

    @cache[session.key] = session
  end

  def delete(key)
    @cache.delete(key)
    path = @sessions_dir / "#{_safe_filename(key)}.jsonl"
    path.delete if path.exist?
    true
  end

  def list_sessions
    sessions = []
    @sessions_dir.glob("*.jsonl").each do |path|
      first_line = path.readlines.first
      next unless first_line

      data = JSON.parse(first_line)
      next unless data["_type"] == "metadata"

      sessions << {
        key: path.basename.to_s.delete_suffix(".jsonl").tr("_", ":"),
        created_at: data["created_at"],
        updated_at: data["updated_at"],
        path: path.to_s
      }
    end
    sessions.sort_by { |s| s[:updated_at] }.reverse
  end

  private

  def _load(key)
    path = @sessions_dir / "#{_safe_filename(key)}.jsonl"
    return nil unless path.exist?

    messages = []
    metadata = {}
    created_at = nil

    path.each_line do |line|
      next if line.strip.empty?

      data = JSON.parse(line)
      if data["_type"] == "metadata"
        metadata = data["metadata"] || {}
        created_at = Time.iso8601(data["created_at"]) if data["created_at"]
      else
        messages << {
          role: data["role"],
          content: data["content"],
          timestamp: data["timestamp"]
        }
      end
    end

    Session.new(key, messages: messages, created_at: created_at, metadata: metadata)
  end

  def _safe_filename(str)
    str.gsub(/[^a-zA-Z0-9._-]/, "_")
  end
end
```

---

## 6. Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Project setup (Gemfile, structure)
- [ ] Message Bus (queue-based)
- [ ] Event data classes
- [ ] Configuration management (YAML/JSON)
- [ ] Basic logging setup

**Deliverable**: Working message bus with producer/consumer

### Phase 2: Agent Core (Week 2-3)
- [ ] Tool base class and registry
- [ ] Basic tools (file read/write, shell exec)
- [ ] LLM provider abstraction
- [ ] Context builder
- [ ] Agent loop (main processing)
- [ ] Session manager

**Deliverable**: Can process a message through LLM with basic tools

### Phase 3: Channels (Week 3-4)
- [ ] Base channel abstraction
- [ ] Telegram channel
- [ ] Discord channel
- [ ] Channel manager
- [ ] Integration with agent loop

**Deliverable**: Can receive messages from Telegram/Discord and send responses

### Phase 4: Advanced Features (Week 4-5)
- [ ] Web tools (search, fetch)
- [ ] Message tool
- [ ] Subagent spawning
- [ ] Memory system
- [ ] Cron scheduling

**Deliverable**: Full multi-channel bot with advanced capabilities

### Phase 5: CLI & Deployment (Week 5-6)
- [ ] CLI commands (Thor)
- [ ] onboard command
- [ ] agent command (single message)
- [ ] gateway command (multi-channel)
- [ ] cron command
- [ ] Docker support

**Deliverable**: Production-ready CLI interface

### Phase 6: Polish & Testing (Week 6-7)
- [ ] Unit tests
- [ ] Integration tests
- [ ] Error handling improvements
- [ ] Documentation
- [ ] Performance optimization

**Deliverable**: Fully tested, documented Ruby nanobot

---

## 7. Key Implementation Challenges & Solutions

### Challenge 1: Async Concurrency Model

**Python**: asyncio with async/await
**Ruby Options**:
- **Fibers**: Lightweight, cooperative multitasking
- **Threads**: Preemptive, but slower
- **Async gem**: New async/await-like API

**Recommendation**: Use Thread for simplicity initially, consider Fiber/Async for optimization

```ruby
# Simple thread-based approach
Thread.new do
  agent_loop.run
end

Thread.new do
  channel_manager.dispatch_outbound
end
```

### Challenge 2: Multi-Provider LLM Support

**Python**: LiteLLM library handles everything
**Ruby**: No equivalent library

**Recommendation**: Build thin adapter layer

```ruby
class Nanobot::Providers::LiteLLMProvider
  def initialize(api_key, api_base, default_model)
    # Detect provider from api_key or api_base
    # Set appropriate environment variables
    # Make HTTP calls via Faraday
  end

  def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
    # Normalize to OpenAI format
    # Make request
    # Parse and return normalized response
  end
end
```

### Challenge 3: WebSocket Channels (Discord, Feishu)

**Python**: Native websockets library with asyncio
**Ruby**: websocket-eventmachine or similar

**Recommendation**: Use discordrb gem for Discord (handles WebSocket), write Feishu adapter

```ruby
require 'discordrb'

bot = Discordrb::Commands::CommandBot.new(token: config.token)

bot.message do |event|
  message = Nanobot::Bus::Events::InboundMessage.new(
    channel: "discord",
    sender_id: event.author.id.to_s,
    chat_id: event.channel.id.to_s,
    content: event.message.content
  )

  bus.publish_inbound(message)
end

bot.run
```

### Challenge 4: JSON Schema Validation

**Python**: Pydantic + validators
**Ruby**: dry-validation or custom

**Recommendation**: Use dry-validation or roll custom validator

```ruby
def validate_params(params)
  errors = []
  schema = parameters || {}

  # Type checking
  expected_type = TYPE_MAP[schema["type"]]
  unless params.is_a?(expected_type)
    errors << "Expected #{schema['type']}"
  end

  # Required fields
  (schema["required"] || []).each do |field|
    errors << "Missing required field: #{field}" unless params.has_key?(field)
  end

  errors
end
```

---

## 8. Testing Strategy

### Unit Tests
```ruby
# spec/unit/agent/tools/read_file_tool_spec.rb
describe Nanobot::Agent::Tools::ReadFileTool do
  it "reads file contents" do
    tool = described_class.new
    result = tool.execute(path: __FILE__)
    expect(result).to include("describe")
  end

  it "respects workspace restrictions" do
    tool = described_class.new(allowed_dir: Pathname.new("/home/user"))
    result = tool.execute(path: "/etc/passwd")
    expect(result).to include("Error")
  end
end
```

### Integration Tests
```ruby
# spec/integration/agent_loop_spec.rb
describe Nanobot::Agent::Loop do
  it "processes a message with tool execution" do
    bus = Nanobot::Bus::MessageBus.new
    provider = MockLLMProvider.new
    loop = described_class.new(bus: bus, provider: provider, workspace: workspace)

    msg = InboundMessage.new(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "Read /path/to/file.txt"
    )

    response = loop.process_message(msg)
    expect(response.content).to include("file contents")
  end
end
```

---

## 9. Configuration Structure

### config.yaml (or config.json)

```yaml
providers:
  openrouter:
    api_key: "sk-or-v1-xxx"
  anthropic:
    api_key: "sk-ant-xxx"

agents:
  defaults:
    model: "anthropic/claude-opus-4-5"
    workspace: "~/.nanobot/workspace"
    max_tokens: 8192
    temperature: 0.7
    max_tool_iterations: 20

channels:
  telegram:
    enabled: true
    token: "YOUR_BOT_TOKEN"
    allow_from:
      - "123456789"
  discord:
    enabled: true
    token: "YOUR_BOT_TOKEN"
    allow_from:
      - "987654321"

gateway:
  host: "0.0.0.0"
  port: 18790

tools:
  web:
    search:
      api_key: "BRAVE_SEARCH_API_KEY"
  exec:
    timeout: 60
  restrict_to_workspace: false
```

---

## 10. Deployment Considerations

### Local Development
```bash
ruby bin/nanobot onboard
ruby bin/nanobot agent -m "Hello"
ruby bin/nanobot gateway
```

### Docker
```dockerfile
FROM ruby:3.2-slim

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["ruby", "bin/nanobot"]
```

### Environment Variables
```bash
NANOBOT_CONFIG_PATH=~/.nanobot/config.json
NANOBOT_WORKSPACE=~/.nanobot/workspace
OPENROUTER_API_KEY=sk-or-v1-xxx
```

---

## 11. Similarities & Differences Summary

### What's the Same
- Architecture (message bus, agent loop, tools)
- Configuration structure
- Session storage (JSONL)
- Tool system design
- Channel abstraction pattern

### What's Different
- Async model (threads vs asyncio)
- Type system (no type hints, use documentation)
- Package manager (Bundler vs pip)
- Standard library differences
- Gem ecosystem is smaller but mature

### Key Adaptations
| Python | Ruby |
|--------|------|
| asyncio | Thread / Fiber / Async |
| Pydantic | dry-validation / Struct |
| @dataclass | Struct / OpenStruct |
| abc.ABC | module / class inheritance |
| typing module | YARD documentation |
| pathlib.Path | Pathname |
| json module | JSON library (stdlib) |
| asyncio.subprocess | Process / Open3 |
| dict | Hash |
| list comprehension | Array#map, select |

---

## 12. Success Criteria

- [ ] Processes single messages through LLM
- [ ] Executes tool calls (file ops, shell, web)
- [ ] Persists conversation history in JSONL
- [ ] Receives messages from Telegram
- [ ] Sends responses through Telegram
- [ ] Supports multiple LLM providers
- [ ] Handles errors gracefully
- [ ] Configuration via JSON/YAML
- [ ] CLI interface (onboard, agent, gateway, cron)
- [ ] ~4000-5000 lines of code
- [ ] Unit tests (80%+ coverage)
- [ ] Documentation

---

## 13. Resources & References

### Ruby Gems
- **thor**: https://github.com/rails/thor
- **dry-rb**: https://dry-rb.org/
- **faraday**: https://lostisland.github.io/faraday/
- **rufus-scheduler**: https://github.com/jmettraux/rufus-scheduler
- **telegram-bot-ruby**: https://github.com/atipugin/telegram-bot-ruby
- **discordrb**: https://github.com/shardlab/discordrb

### Similar Ruby Projects
- **lita**: Ruby chatbot framework
- **hubot**: Node but could inspire design

### LLM Resources
- **OpenRouter API**: https://openrouter.ai/
- **Anthropic API**: https://www.anthropic.com/
- **Function Calling**: https://openrouter.ai/docs#function-calling

---

## 14. Example Usage (Target)

```ruby
# Initialization
config = Nanobot::Config::Loader.load("~/.nanobot/config.json")
workspace = Pathname.new(config.agents.defaults.workspace).expand_path

# Create components
bus = Nanobot::Bus::MessageBus.new
provider = Nanobot::Providers::LiteLLMProvider.new(
  api_key: config.providers.openrouter.api_key,
  default_model: config.agents.defaults.model
)
agent_loop = Nanobot::Agent::Loop.new(
  bus: bus,
  provider: provider,
  workspace: workspace
)
channel_manager = Nanobot::Channels::Manager.new(config.channels, bus)

# Start agent
agent_thread = Thread.new { agent_loop.run }
channel_manager.start

# Keep running
agent_thread.join
```

---

## Conclusion

The Ruby port should maintain Nanobot's philosophy of lightweight, clean, extensible code while leveraging Ruby's strengths in conciseness and community gems. The main challenge is managing concurrency (asyncio → threads) and building adapters for multi-provider LLM support, but both are well within Ruby's capabilities.

**Start with the message bus and core agent loop, then layer on channels and features iteratively.**
