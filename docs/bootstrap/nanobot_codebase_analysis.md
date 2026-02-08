# Nanobot Codebase Analysis - Comprehensive Overview

**Project**: Nanobot - Ultra-Lightweight Personal AI Assistant
**Version**: 0.1.3.post4
**Language**: Python 3.11+
**Total Lines of Code**: ~4,747 Python lines (core agent ~3,422 lines)
**Total Project Size**: 65MB (mostly images and documentation)
**Python Files**: 46 files
**License**: MIT

---

## 1. Project Purpose & Architecture

### What is Nanobot?

Nanobot is an ultra-lightweight personal AI assistant framework that emphasizes:
- **Minimal footprint**: ~4,000 lines of core code vs 430k+ in competitors like Clawdbot
- **Research-ready**: Clean, readable code for easy understanding and modification
- **Fast startup**: Minimal dependencies, quick iteration
- **Multi-channel**: Works with Telegram, Discord, WhatsApp, Feishu
- **Extensible**: Modular architecture for adding skills and tools

### Core Architecture Pattern

Nanobot follows an **agent loop + message bus** architecture:

```
Chat Channels (Telegram, Discord, etc.)
         ↓
    Message Bus (Queue-based)
         ↓
    Agent Loop (Core Processing)
    - Context Builder (Prompts)
    - LLM Provider (Chat)
    - Tool Registry (Execution)
    - Session Manager (History)
         ↓
    Message Bus (Response Queue)
         ↓
    Chat Channels (Send Responses)
```

**Key Design Principles**:
- Decoupled channels from agent core via message bus
- Async/await throughout for concurrency
- Stateless agent loop with session-based history
- Configuration-driven deployment
- Security sandboxing available

---

## 2. Core Components & Module Structure

### 2.1 Agent Module (`nanobot/agent/`)

The heart of the system - handles conversation logic and tool execution.

#### Key Files:

**`loop.py`** - Main Agent Loop
- Core processing engine that handles message->response pipeline
- **Responsibilities**:
  - Receives messages from bus
  - Builds context (history + prompts + memory)
  - Calls LLM in a loop (agentic loop pattern)
  - Executes tool calls returned by LLM
  - Sends responses back to bus
- **Key Class**: `AgentLoop`
  - `run()` - Main async loop that processes messages
  - `_process_message()` - Single message handler
  - `process_direct()` - CLI/direct message processing
  - Max iterations: 20 (configurable) to prevent infinite loops

**`context.py`** - Prompt & Context Building
- Assembles the system prompt and message context for LLM calls
- **Key Components**:
  - Bootstrap files (AGENTS.md, SOUL.md, USER.md, TOOLS.md, IDENTITY.md)
  - Memory context (long-term + daily notes)
  - Skills summaries
  - Runtime information (OS, Python version, workspace location)
- **Key Class**: `ContextBuilder`
  - `build_system_prompt()` - Creates full system prompt
  - `build_messages()` - Assembles message list for LLM
  - `_build_user_content()` - Handles base64-encoded media (images)

**`memory.py`** - Persistent Memory System
- Two-tier memory: long-term (MEMORY.md) and daily notes (YYYY-MM-DD.md)
- **Key Class**: `MemoryStore`
  - `read_long_term()` / `write_long_term()` - Long-term persistent memory
  - `read_today()` / `append_today()` - Daily notes
  - `get_memory_context()` - Formats memory for agent prompts

**`skills.py`** - Skills Loader
- Loads and manages skill plugins
- Skills can be "always-loaded" (full content in prompt) or on-demand (agent reads via file tool)

**`subagent.py`** - Background Task Execution
- Spawns lightweight agent instances for background tasks
- Tasks run isolated but announce results back to origin channel
- Uses same LLM provider but isolated context

**`tools/` - Built-in Tool Implementations**
- See section 2.2 below

### 2.2 Tools Module (`nanobot/agent/tools/`)

Provides capabilities for agents to interact with the environment.

#### Tool System Design:

- **Base Class**: `Tool` (ABC)
  - All tools inherit from this abstract base
  - Implement: `name`, `description`, `parameters`, `execute()`
  - Parameter validation using JSON Schema
  - `to_schema()` exports to OpenAI function format

- **Tool Registry**: `ToolRegistry`
  - Dynamic tool registration/unregistration
  - `execute()` method with error handling
  - Exports all tools as OpenAI function schemas

#### Built-in Tools:

1. **File Tools** (`filesystem.py`)
   - `ReadFileTool` - Read file contents
   - `WriteFileTool` - Write new files
   - `EditFileTool` - Edit existing files (replacement-based)
   - `ListDirTool` - List directory contents
   - Security: Can restrict to workspace directory

2. **Shell Tool** (`shell.py`)
   - `ExecTool` - Execute shell commands
   - Security: Deny patterns prevent dangerous commands (rm -rf, reboot, etc.)
   - Timeout: Configurable (default 60s)
   - Can restrict to workspace directory

3. **Web Tools** (`web.py`)
   - `WebSearchTool` - Search using Brave Search API
   - `WebFetchTool` - Fetch and parse web pages
   - Returns cleaned markdown content

4. **Message Tool** (`message.py`)
   - `MessageTool` - Send messages to specific chat channels
   - Context-aware: knows current channel/chat_id
   - Used for proactive notifications

5. **Spawn Tool** (`spawn.py`)
   - `SpawnTool` - Spawn background subagents
   - Delegates to SubagentManager
   - Useful for long-running tasks

6. **Cron Tool** (`cron.py`)
   - `CronTool` - Manage scheduled tasks
   - Delegates to CronService

### 2.3 Bus Module (`nanobot/bus/`)

Message queue system decoupling channels from agent.

**`queue.py`** - `MessageBus` class
- Async message queues (inbound/outbound)
- Publisher-subscriber pattern for outbound messages
- `publish_inbound()` - Channels send messages to agent
- `consume_inbound()` - Agent reads messages
- `publish_outbound()` / `consume_outbound()` - Agent sends responses
- `subscribe_outbound()` - Channels subscribe to responses

**`events.py`** - Event Data Classes
- `InboundMessage` - Message from channel (channel, sender_id, chat_id, content, media, metadata)
- `OutboundMessage` - Response to channel

### 2.4 Channels Module (`nanobot/channels/`)

Integrations with chat platforms.

**`base.py`** - `BaseChannel` ABC
- Abstract interface for all channel implementations
- Key methods:
  - `start()` - Connect and listen
  - `stop()` - Clean up
  - `send()` - Send message
  - `is_allowed()` - Check access control via allowFrom list
  - `_handle_message()` - Receive message from platform

**Channel Implementations**:

1. **Telegram** (`telegram.py`)
   - Uses `python-telegram-bot` library
   - Long polling to receive messages
   - Per-user access control
   - Proxy support for regions with restrictions

2. **Discord** (`discord.py`)
   - Gateway connection (WebSocket)
   - Message content intent required
   - Per-user access control

3. **WhatsApp** (`whatsapp.py`)
   - Bridge integration (Node.js/TypeScript)
   - Scan QR code to link device
   - Per-user phone number access control

4. **Feishu** (`feishu.py`)
   - WebSocket long connection (no public IP needed)
   - Uses Feishu Open Platform APIs
   - Per-user access control

**Manager** (`manager.py`)
- `ChannelManager` - Orchestrates all channels
- Starts/stops channels
- Manages bus subscriptions

### 2.5 Providers Module (`nanobot/providers/`)

LLM provider abstraction layer.

**`base.py`** - Provider Base Classes
- `LLMProvider` (ABC) - Abstract provider interface
- `LLMResponse` - Response dataclass with content and tool_calls
- `ToolCallRequest` - Tool call dataclass

**`litellm_provider.py`** - `LiteLLMProvider`
- Unified interface to multiple LLM providers via LiteLLM library
- **Supported Providers**:
  - OpenRouter (multi-provider access)
  - Anthropic (Claude direct)
  - OpenAI (GPT direct)
  - DeepSeek (DeepSeek direct)
  - Groq (fast LLM + Whisper transcription)
  - Gemini (Gemini direct)
  - DashScope (Qwen/Alibaba)
  - Zhipu (GLM)
  - Moonshot/Kimi
  - AiHubMix (API gateway)
  - vLLM (local LLM server)
- Auto-configures environment variables based on detected provider
- Handles OpenAI function calling format

**`transcription.py`** - Voice Transcription
- Groq Whisper integration for voice message transcription

### 2.6 Session Module (`nanobot/session/`)

Conversation history management.

**`manager.py`** - `SessionManager` class
- JSONL-based persistent storage
- Per-session files in `~/.nanobot/sessions/`
- **Key Methods**:
  - `get_or_create()` - Get or create session by key
  - `save()` - Persist session to disk
  - `get_history()` - Get last N messages in LLM format
- **Session Key Format**: `{channel}:{chat_id}`
- Cached in memory for performance

### 2.7 Config Module (`nanobot/config/`)

Configuration management.

**`schema.py`** - Pydantic Config Classes
- `Config` - Top-level config (not fully shown, likely aggregates below)
- **Channel Configs**:
  - `TelegramConfig` - token, allow_from, proxy
  - `DiscordConfig` - token, allow_from, intents
  - `WhatsAppConfig` - bridge_url, allow_from
  - `FeishuConfig` - app_id, app_secret, allow_from
- **Provider Configs**:
  - `ProvidersConfig` - All provider API keys/endpoints
  - `ProviderConfig` - Individual provider (api_key, api_base, extra_headers)
- **Agent Config**:
  - `AgentsConfig` → `AgentDefaults`
  - model, max_tokens, temperature, max_tool_iterations
  - workspace location
- **Other**:
  - `GatewayConfig` - Server host/port
  - `WebSearchConfig` - Brave Search API key
  - `ExecToolConfig` - Shell timeout, security patterns

**`loader.py`** - Config I/O
- JSON file reading from `~/.nanobot/config.json`
- Default values
- Validation

### 2.8 Cron Module (`nanobot/cron/`)

Scheduled task system.

**`service.py`** - `CronService`
- Job scheduling and execution
- Multiple schedule types: `at` (one-time), `every` (interval), `cron` (cron expression)
- Persistent storage of jobs
- Async job execution with callbacks

**`types.py`** - Data Classes
- `CronJob` - Job definition
- `CronSchedule` - Schedule specification
- `CronPayload` - Job payload

### 2.9 Heartbeat Module (`nanobot/heartbeat/`)

Proactive wake-up and health checks.

**`service.py`** - `HeartbeatService`
- Periodically triggers agent to check for updates
- Useful for proactive notifications

### 2.10 CLI Module (`nanobot/cli/`)

Command-line interface.

**`commands.py`** - CLI Commands (using Typer)
- `onboard` - Initialize config and workspace
- `agent` - Interactive or single-message chat
- `gateway` - Start multi-channel gateway
- `status` - Show system status
- `channels` - Channel management (WhatsApp linking)
- `cron` - Scheduled task management
- Workspace template file creation

---

## 3. Dependencies & External Libraries

### Core Dependencies (from pyproject.toml):

```
typer>=0.9.0                    # CLI framework
litellm>=1.0.0                  # LLM provider abstraction
pydantic>=2.0.0                 # Data validation
pydantic-settings>=2.0.0        # Settings from environment/files
websockets>=12.0                # WebSocket client
websocket-client>=1.6.0         # Alternative WebSocket library
httpx>=0.25.0                   # Async HTTP client
loguru>=0.7.0                   # Logging
readability-lxml>=0.8.0         # Web page parsing
rich>=13.0.0                    # Rich CLI output
croniter>=2.0.0                 # Cron expression parsing
python-telegram-bot>=21.0       # Telegram API
lark-oapi>=1.0.0                # Feishu (Lark) Open API
```

### Optional Dependencies:
- `pytest>=7.0.0` - Testing
- `pytest-asyncio>=0.21.0` - Async test support
- `ruff>=0.1.0` - Code linting/formatting

### Runtime Requirements:
- Python 3.11+
- An LLM provider API key (OpenRouter, Anthropic, OpenAI, etc.)
- (Optional) Brave Search API key for web search
- (Optional) Groq API key for voice transcription
- (Optional) Node.js 18+ for WhatsApp integration

---

## 4. Main Entry Points & Workflows

### 4.1 CLI Entry Point

```python
# Entry: nanobot command
nanobot.cli.commands:app
# Typer app with commands: onboard, agent, gateway, status, channels, cron
```

### 4.2 Configuration Initialization Workflow

```
user runs: nanobot onboard
    ↓
get_config_path() → ~/.nanobot/config.json
    ↓
create default Config object (Pydantic)
    ↓
save_config() → JSON file
    ↓
create workspace at ~/.nanobot/workspace
    ↓
populate bootstrap template files:
  - AGENTS.md
  - SOUL.md
  - USER.md
  - TOOLS.md
    ↓
user manually edits config.json to add API keys
```

### 4.3 Direct Chat Workflow (Single Message)

```
user runs: nanobot agent -m "Question"
    ↓
load config → create LLMProvider (LiteLLMProvider)
    ↓
create AgentLoop with MessageBus
    ↓
process_direct() → InboundMessage
    ↓
_process_message() loop:
    1. build_system_prompt() from workspace files
    2. get_history() from session
    3. call LLM with messages + tools
    4. if tool_calls:
         - execute each tool
         - add tool results to messages
         - repeat from step 3
    5. else: return response
    ↓
save message to session history
    ↓
print response
```

### 4.4 Gateway/Multi-Channel Workflow

```
user runs: nanobot gateway
    ↓
load config → create LLMProvider
    ↓
create ChannelManager with all enabled channels
    ↓
for each channel:
    create Channel instance
    channel.start() (async, long-running)
    ↓
    Channel listens for messages from platform
    ↓
    on_message: _handle_message()
        - check is_allowed()
        - create InboundMessage
        - bus.publish_inbound()
    ↓
create AgentLoop + MessageBus
    ↓
agent_loop.run() (async, main processing loop)
    ↓
wait_for_inbound_messages()
    ↓
_process_message() (same as 4.3 above)
    ↓
bus.publish_outbound(OutboundMessage)
    ↓
dispatch_outbound() sends to subscribed channels
    ↓
each channel.send() delivers to platform
```

### 4.5 Background Task (Subagent) Workflow

```
agent encounters spawn tool call with task
    ↓
spawn_tool.execute(task, label, origin_channel, origin_chat_id)
    ↓
SubagentManager.spawn():
    - create unique task_id
    - create background asyncio.Task
    - run _run_subagent() async
    ↓
    return "Task started" immediately
    ↓
_run_subagent() (background):
    1. create isolated agent context
    2. call LLM with task
    3. execute tools same as main agent
    4. when done:
        - format announce message
        - publish to bus as "system" channel message
        - include origin_channel:origin_chat_id in chat_id
    ↓
main agent receives system message
    ↓
_process_system_message() handles it
    ↓
routes response back to origin_channel
```

### 4.6 Scheduled Task Workflow

```
user runs: nanobot cron add --name "daily" --message "Hello" --cron "0 9 * * *"
    ↓
CronService.add_job() stores job definition
    ↓
CronService.start() (background task)
    ↓
timer loop checks job schedules
    ↓
on schedule trigger:
    - create task message from job.payload
    - call on_job callback (usually agent.process_direct)
    - announcement sent to user
```

---

## 5. Key Features & Functionality

### 5.1 Core Features

1. **Multi-Provider LLM Support**
   - Unified interface via LiteLLM
   - All major providers supported
   - Easy switching between models

2. **Tool-Calling Agent Loop**
   - LLM returns tool calls
   - Agent executes tools
   - Results fed back to LLM
   - Iterates until response (max 20 iterations)

3. **Multi-Channel Communication**
   - Telegram, Discord, WhatsApp, Feishu
   - Access control per channel (allowFrom list)
   - Message bus decoupling

4. **Persistent Memory**
   - Long-term memory (MEMORY.md)
   - Daily notes (YYYY-MM-DD.md)
   - Included in agent context

5. **Conversation Sessions**
   - Per-user/chat persistent history
   - JSONL-based storage
   - Metadata tracking

6. **Skills System**
   - Bundled skills (github, weather, tmux, cron, skill-creator)
   - Always-loaded vs on-demand
   - Extensible architecture

7. **Scheduled Tasks**
   - One-time, interval, and cron schedules
   - Persistent job storage
   - Async execution

8. **Background Tasks**
   - Subagent spawning
   - Isolated context
   - Result announcements

9. **Security Features**
   - Access control lists (allowFrom)
   - Workspace sandboxing (restrictToWorkspace)
   - Command deny patterns
   - Path traversal protection

### 5.2 Built-in Capabilities (Tools)

- **File Operations**: Read, write, edit, list
- **Shell Execution**: Command execution with security guards
- **Web Browsing**: Search (Brave) + fetch/parse
- **Chat**: Send messages to channels
- **Background Tasks**: Spawn subagents
- **Scheduling**: Manage cron jobs

### 5.3 Extensibility Points

1. **Custom Tools**: Inherit from `Tool`, implement interface
2. **Custom Skills**: Add to skills/ directory
3. **Custom Channels**: Inherit from `BaseChannel`
4. **Custom Providers**: Inherit from `LLMProvider`
5. **Bootstrap Files**: AGENTS.md, SOUL.md, USER.md, etc.

---

## 6. Configuration & Customization

### Configuration File: `~/.nanobot/config.json`

```json
{
  "providers": {
    "openrouter": {
      "apiKey": "sk-or-v1-xxx"
    },
    "anthropic": {
      "apiKey": "sk-ant-xxx"
    }
  },
  "agents": {
    "defaults": {
      "model": "anthropic/claude-opus-4-5",
      "workspace": "~/.nanobot/workspace"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "YOUR_BOT_TOKEN",
      "allowFrom": ["YOUR_USER_ID"]
    }
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 18790
  },
  "tools": {
    "web": {
      "search": {
        "apiKey": "BRAVE_SEARCH_API_KEY"
      }
    },
    "exec": {
      "timeout": 60
    },
    "restrictToWorkspace": false
  }
}
```

### Workspace Files

Located at `~/.nanobot/workspace/`:

```
workspace/
  ├── AGENTS.md         # Agent instructions/personality
  ├── SOUL.md           # Agent soul/values
  ├── USER.md           # User profile/preferences
  ├── TOOLS.md          # Tool usage documentation
  ├── IDENTITY.md       # Optional identity info
  ├── memory/
  │   ├── MEMORY.md     # Long-term persistent memory
  │   └── YYYY-MM-DD.md # Daily notes (auto-created)
  └── sessions/         # Conversation history (JSONL files)
```

---

## 7. Data Flow Diagrams

### Message Processing Flow

```
InboundMessage (channel, sender_id, chat_id, content)
         ↓
    MessageBus.inbound
         ↓
AgentLoop.consume_inbound()
         ↓
SessionManager.get_or_create(session_key)
         ↓
ContextBuilder.build_messages(
    system_prompt,
    history,
    current_message
)
         ↓
LLMProvider.chat(messages, tools)
         ↓
┌─────────────────┐
│ LLMResponse     │
├─────────────────┤
│ - content       │
│ - tool_calls[]  │
│ - finish_reason │
└─────────────────┘
         ↓
    [Loop if tool_calls]
    ↓
    ToolRegistry.execute(tool_name, params)
    ↓
    Tool.execute(**kwargs) → result
    ↓
    ContextBuilder.add_tool_result()
    ↓
    LLMProvider.chat() again
    ↓
    [Until no tool_calls]
         ↓
OutboundMessage (channel, chat_id, content)
         ↓
    MessageBus.outbound
         ↓
ChannelManager.dispatch_outbound()
         ↓
Channel.send(message)
         ↓
Chat Platform (Telegram, Discord, etc.)
```

### System Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Chat Platforms                            │
│  (Telegram, Discord, WhatsApp, Feishu, CLI, etc.)           │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┴─────────────┐
         ↓                           ↓
    ChannelManager          WebSocket/Poll Listeners
         │                           │
         └─────────────┬─────────────┘
                       ↓
              ┌────────────────────┐
              │   Message Bus      │
              ├────────────────────┤
              │ - inbound queue    │
              │ - outbound queue   │
              │ - subscribers      │
              └────────────────────┘
                       ↑
                       │
    ┌──────────────────┴──────────────────┐
    │      Agent Loop (Main Loop)         │
    ├─────────────────────────────────────┤
    │ - Message processing                │
    │ - Context building                  │
    │ - LLM orchestration                 │
    │ - Tool execution                    │
    └──────────────────┬──────────────────┘
         ↑             │             ↑
         │             ↓             │
    ┌────────────┐ ┌─────────┐ ┌──────────────┐
    │ Session    │ │LLM      │ │ Tool         │
    │ Manager    │ │Provider │ │ Registry     │
    │            │ │         │ │              │
    │ - History  │ │         │ │ - ReadFile   │
    │ - Metadata │ │         │ │ - WriteFile  │
    │            │ │         │ │ - ExecShell  │
    │            │ │         │ │ - WebSearch  │
    │            │ │         │ │ - Message    │
    │            │ │         │ │ - Spawn      │
    │            │ │         │ │ - Cron       │
    └────────────┘ └─────────┘ └──────────────┘
         ↑
    ┌────────────────┐
    │ Context        │
    │ Builder        │
    ├────────────────┤
    │ - System       │
    │   prompt       │
    │ - Memory       │
    │ - Skills       │
    └────────────────┘
         ↑
    ┌────────────────────────┐
    │ Workspace Files        │
    ├────────────────────────┤
    │ - AGENTS.md            │
    │ - SOUL.md              │
    │ - USER.md              │
    │ - memory/MEMORY.md     │
    │ - memory/YYYY-MM-DD.md │
    └────────────────────────┘
```

---

## 8. Workflows & Process Flows

### 8.1 Complete Agent Conversation Flow

```
User Message
    ↓
Channel receives message from platform
    ↓
InboundMessage created with:
  - channel: "telegram" | "discord" | etc
  - sender_id: user identifier
  - chat_id: conversation identifier
  - content: message text
  - media: optional image paths
    ↓
_handle_message() called on channel
    ↓
is_allowed(sender_id) checked
  → if denied, log warning and return
    ↓
bus.publish_inbound(InboundMessage)
    ↓
MessageBus enqueues to inbound queue
    ↓
AgentLoop.run() continuously consumes
    ↓
AgentLoop.consume_inbound() gets message
    ↓
_process_message(InboundMessage) called
    ↓
SessionManager.get_or_create(channel:chat_id)
    ↓
Update tool contexts with current channel/chat_id
    ↓
ContextBuilder.build_messages():
  1. build_system_prompt():
     - runtime info (OS, Python, workspace)
     - bootstrap files (AGENTS.md, SOUL.md, etc)
     - memory context (long-term + today)
     - skills summary
  2. append history from session
  3. append current message
    ↓
AGENT LOOP (max 20 iterations):
  ↓
  1. LLMProvider.chat(
       messages=[system, history..., user],
       tools=[tool_schemas],
       model="anthropic/claude-opus-4-5"
     )
  ↓
  2. LLMResponse returned:
     - content: text response
     - tool_calls: list of function calls
     - finish_reason: "tool_calls" | "end_turn"
  ↓
  3. Add assistant message with tool_calls to messages
  ↓
  4. For each tool_call:
     a. ToolRegistry.execute(tool_name, params)
     b. Tool.validate_params() checks JSON schema
     c. Tool.execute(**kwargs) runs
     d. Result formatted as string
     e. ContextBuilder.add_tool_result() adds to messages
  ↓
  5. Check if more tool_calls:
     - if yes: repeat from step 1
     - if no: final_content = response.content, break
  ↓
Final response obtained
    ↓
Session.add_message("user", content)
Session.add_message("assistant", final_content)
SessionManager.save(session)
    ↓
OutboundMessage created:
  - channel: same as input
  - chat_id: same as input
  - content: final_content
    ↓
bus.publish_outbound(OutboundMessage)
    ↓
MessageBus.dispatch_outbound() routes to subscribers
    ↓
Channel.send(message) called
    ↓
Channel implementation sends to platform
    ↓
User receives response
```

### 8.2 Tool Execution Flow

```
LLM decides to call tool
    ↓
Response includes:
{
  "tool_calls": [
    {
      "id": "call_xxx",
      "function": {
        "name": "read_file",
        "arguments": "{\"path\": \"/path/to/file\"}"
      }
    }
  ]
}
    ↓
ToolRegistry.execute("read_file", {"path": "/path/to/file"})
    ↓
1. Get tool from registry: self._tools["read_file"]
2. Validate params with tool.validate_params(params)
   - Check JSON schema
   - Return error list if invalid
3. Call tool.execute(**params) → coroutine
4. Catch exceptions, return error string
    ↓
ReadFileTool.execute(path="/path/to/file")
    ↓
1. If restrict_to_workspace: check path is within allowed_dir
2. Read file contents
3. Return text (or error)
    ↓
Result string returned to ToolRegistry.execute()
    ↓
Format as tool result:
{
  "role": "tool",
  "tool_call_id": "call_xxx",
  "name": "read_file",
  "content": "file contents..."
}
    ↓
Add to messages list
    ↓
Call LLM again with updated messages
```

---

## 9. Security Model

### Access Control

1. **Channel-level**: `allowFrom` whitelist per channel
   - Empty list = allow all
   - List of user IDs/phone numbers = allow only those

2. **Workspace Sandboxing**: `restrictToWorkspace: true`
   - All file operations limited to workspace directory
   - All shell commands run in workspace directory
   - Path traversal impossible

3. **Command Blocking**: ExecTool deny patterns prevent:
   - `rm -rf` / `rmdir /s`
   - Disk operations (format, mkfs, dd)
   - System power (shutdown, reboot)
   - Fork bombs

### Configuration Security

- API keys stored in `~/.nanobot/config.json` (local only)
- LiteLLM handles provider auth securely
- WebSocket connections for channels (no public IP needed)

---

## 10. Code Statistics

### Module Sizes (approximate Python LOC)

```
agent/loop.py          ~350 lines
agent/context.py       ~200 lines
agent/memory.py        ~100 lines
agent/session/         ~200 lines
agent/tools/           ~700 lines (across multiple files)
  - filesystem.py      ~150 lines
  - shell.py           ~100 lines
  - web.py             ~150 lines
  - base.py            ~100 lines
  - registry.py        ~80 lines

bus/                   ~150 lines
channels/              ~1000 lines (all implementations)
  - telegram.py        ~250 lines
  - discord.py         ~250 lines
  - whatsapp.py        ~200 lines
  - feishu.py          ~250 lines
  - base.py            ~100 lines

providers/             ~300 lines
config/                ~150 lines
cli/                   ~400 lines
cron/                  ~200 lines
session/               ~200 lines
utils/                 ~50 lines

Total: ~4,747 lines
```

### File Count: 46 Python files

---

## 11. Key Design Patterns

### 1. **Abstract Base Classes (ABC)**
- `Tool` - All tools inherit
- `BaseChannel` - All channels inherit
- `LLMProvider` - All providers inherit

### 2. **Registry Pattern**
- `ToolRegistry` - Dynamic tool registration/lookup

### 3. **Message Bus Pattern**
- Decouples channels from agent core
- Async queue-based communication
- Publisher-subscriber for responses

### 4. **Agentic Loop**
- LLM → Tool Calls → Execute → Loop back
- Max iteration limit to prevent infinite loops

### 5. **Context Building**
- Composable prompt construction
- Memory integration
- Skill loading

### 6. **Session Management**
- Per-user conversation history
- JSONL persistent storage
- LRU caching

### 7. **Async/Await**
- All I/O is async
- Concurrent channel listeners
- Background task spawning

---

## 12. Comparison: Python vs Ruby Port Considerations

### What Translates Well:
- Architecture (message bus, agent loop, tools)
- Module structure
- Configuration management
- Session/memory storage
- Tool system

### Key Differences to Consider:

1. **Async Model**
   - Python: asyncio (event loop)
   - Ruby: Fiber, Thread, or Async gem

2. **Type System**
   - Python: Pydantic for validation
   - Ruby: Use dry-types, dry-struct, or custom validators

3. **LLM Integration**
   - Python: LiteLLM library (multi-provider)
   - Ruby: May need to implement providers directly or use wrapper gems

4. **WebSocket Channels**
   - Python: websockets library (native async)
   - Ruby: WebSocket-Eventmachine or similar

5. **Cron Scheduling**
   - Python: croniter + asyncio timer
   - Ruby: whenever gem or rufus-scheduler

6. **CLI Framework**
   - Python: Typer
   - Ruby: Thor or CLI

7. **Configuration**
   - Python: Pydantic-settings
   - Ruby: YAML + Dry-validation or similar

8. **Logging**
   - Python: loguru
   - Ruby: Logger or Log4j gem

9. **Import/Module System**
   - Python: Dynamic imports, __init__.py packages
   - Ruby: require, module/class structure

10. **JSON Handling**
    - Python: json module + dataclasses
    - Ruby: JSON library + Hash/OpenStruct

### Architectural Translation:

```
Python                          Ruby
─────────────────────────────────────────
asyncio loops        →           Fibers/Threads/Async
ABC inheritance      →           Module mixins/inheritance
dataclasses          →           Struct/OpenStruct
Pydantic validation  →           Dry-validation/dry-types
dict/typing          →           Hash/OpenStruct
JSONL files          →           Same
SQLite (optional)    →           Same or SQLite3
httpx (async HTTP)   →           Faraday/Net::HTTP
websockets           →           websocket-eventmachine
```

---

## 13. Summary & Key Takeaways

### What Makes Nanobot Special:
1. **Minimal & Focused**: 4,000 lines vs 430k in competitors
2. **Clean Architecture**: Clear separation of concerns
3. **Multi-Channel**: Works across Telegram, Discord, WhatsApp, Feishu
4. **Extensible**: Plugin tools and skills
5. **Production-Ready**: Security, error handling, persistence
6. **Research-Friendly**: Readable, modifiable code

### Core Concepts for Ruby Port:
1. Message Bus decouples channels from agent
2. Tool system via abstract base + registry
3. Agentic loop: LLM → Tools → Loop
4. Context builder assembles prompts
5. Sessions store conversation history
6. Async throughout for performance

### Critical Implementation Points:
1. Async concurrency model (critical for channels + agent)
2. Message queue/bus implementation
3. LLM provider abstraction
4. Tool parameter validation
5. Session persistence (JSONL)
6. Config management with validation

---

## 14. File Locations Reference

**Source Root**: `/home/budu/source/nanobot/`

**Key Paths**:
- Agent core: `nanobot/agent/loop.py` (main engine)
- Tools: `nanobot/agent/tools/*.py` (all tool implementations)
- Channels: `nanobot/channels/*.py` (Telegram, Discord, etc.)
- Providers: `nanobot/providers/*.py` (LLM providers)
- Config: `nanobot/config/` (schema + loader)
- CLI: `nanobot/cli/commands.py` (entry point)
- Sessions: `~/.nanobot/sessions/` (JSONL conversation files)
- Config: `~/.nanobot/config.json` (user configuration)
- Workspace: `~/.nanobot/workspace/` (memories, bootstrap files)

**Total Project Size**: 65MB
**Python Files**: 46
**Main Python Code**: ~4,747 lines
