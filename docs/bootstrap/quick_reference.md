# Nanobot Codebase - Quick Reference Guide

## Project Summary
- **Language**: Python 3.11+
- **Lines of Code**: 4,747 (46 Python files)
- **Project Size**: 65MB
- **Purpose**: Ultra-lightweight multi-channel AI agent framework
- **Architecture**: Message bus + Agent loop + Tool registry

---

## Core Modules at a Glance

### Agent (`nanobot/agent/`)
| File | Purpose | Key Classes |
|------|---------|------------|
| `loop.py` | Main processing engine | `AgentLoop` |
| `context.py` | Prompt building | `ContextBuilder` |
| `memory.py` | Persistent memory | `MemoryStore` |
| `skills.py` | Skill loading | `SkillsLoader` |
| `subagent.py` | Background tasks | `SubagentManager` |

### Tools (`nanobot/agent/tools/`)
| File | Tool Name | Purpose |
|------|-----------|---------|
| `base.py` | - | Tool ABC |
| `registry.py` | - | Tool registry |
| `filesystem.py` | read_file, write_file, edit_file, list_dir | File operations |
| `shell.py` | exec | Shell commands |
| `web.py` | web_search, web_fetch | Web browsing |
| `message.py` | message | Send messages |
| `spawn.py` | spawn | Background tasks |
| `cron.py` | cron | Schedule tasks |

### Bus (`nanobot/bus/`)
| File | Purpose | Key Classes |
|------|---------|------------|
| `queue.py` | Message queue | `MessageBus` |
| `events.py` | Event types | `InboundMessage`, `OutboundMessage` |

### Channels (`nanobot/channels/`)
| File | Purpose | Key Classes |
|------|---------|------------|
| `base.py` | Channel interface | `BaseChannel` |
| `telegram.py` | Telegram integration | `TelegramChannel` |
| `discord.py` | Discord integration | `DiscordChannel` |
| `whatsapp.py` | WhatsApp integration | `WhatsAppChannel` |
| `feishu.py` | Feishu integration | `FeishuChannel` |
| `manager.py` | Channel orchestration | `ChannelManager` |

### Providers (`nanobot/providers/`)
| File | Purpose | Key Classes |
|------|---------|------------|
| `base.py` | Provider interface | `LLMProvider` |
| `litellm_provider.py` | Multi-provider | `LiteLLMProvider` |
| `transcription.py` | Voice transcription | Groq Whisper |

### Config (`nanobot/config/`)
| File | Purpose |
|------|---------|
| `schema.py` | Config schemas (Pydantic) |
| `loader.py` | Config file loading |

### Session & Memory (`nanobot/session/`, `nanobot/cron/`, etc.)
| File | Purpose | Key Classes |
|------|---------|------------|
| `session/manager.py` | Conversation history | `Session`, `SessionManager` |
| `cron/service.py` | Task scheduling | `CronService` |
| `cron/types.py` | Cron types | `CronJob`, `CronSchedule` |
| `heartbeat/service.py` | Periodic wake-up | `HeartbeatService` |

### CLI (`nanobot/cli/`)
| File | Purpose |
|------|---------|
| `commands.py` | CLI commands (Typer) |

---

## Data Flow Summary

```
Message comes in
    ↓
Channel.on_message() → InboundMessage
    ↓
MessageBus.publish_inbound()
    ↓
AgentLoop.consume_inbound()
    ↓
ContextBuilder.build_messages() [system + history + current]
    ↓
LOOP: LLMProvider.chat() with tools
    ↓
Has tool calls?
    ├─ YES: ToolRegistry.execute() → add results → loop again
    └─ NO: final_content
    ↓
SessionManager.save() [history]
    ↓
MessageBus.publish_outbound()
    ↓
ChannelManager.dispatch() → Channel.send()
    ↓
Response sent to user
```

---

## Key Files by Function

### Start Here
1. `nanobot/__main__.py` - Entry point
2. `nanobot/cli/commands.py` - CLI commands
3. `nanobot/agent/loop.py` - Main agent logic

### Message Routing
1. `nanobot/bus/queue.py` - Message bus
2. `nanobot/channels/base.py` - Channel interface
3. `nanobot/channels/telegram.py` - Example channel

### LLM Integration
1. `nanobot/providers/base.py` - Provider interface
2. `nanobot/providers/litellm_provider.py` - Multi-provider

### Tool System
1. `nanobot/agent/tools/base.py` - Tool interface
2. `nanobot/agent/tools/registry.py` - Tool registry
3. `nanobot/agent/tools/filesystem.py` - File tools

### Context & Prompts
1. `nanobot/agent/context.py` - Prompt building
2. `nanobot/agent/memory.py` - Memory system

### Session Management
1. `nanobot/session/manager.py` - Session storage (JSONL)

---

## Configuration Files

### User Config: `~/.nanobot/config.json`
Contains API keys, channel tokens, model selection, tool settings

### Workspace: `~/.nanobot/workspace/`
```
AGENTS.md       - Agent personality/instructions
SOUL.md         - Agent values
USER.md         - User profile
TOOLS.md        - Tool documentation
IDENTITY.md     - Optional identity info
memory/
  MEMORY.md     - Long-term persistent memory
  YYYY-MM-DD.md - Daily notes (auto-created)
sessions/
  ***.jsonl     - Conversation history files
```

---

## External Dependencies (Key)

### LLM & APIs
- **litellm** - Multi-provider LLM support
- **httpx** - Async HTTP client
- **readability-lxml** - Web page parsing

### Chat Platforms
- **python-telegram-bot** - Telegram
- **websockets** - WebSocket connections
- **lark-oapi** - Feishu/Lark

### Config & Validation
- **pydantic** - Data validation
- **pydantic-settings** - Settings from files/env

### CLI & UX
- **typer** - CLI framework
- **rich** - Rich terminal output
- **loguru** - Advanced logging

### Scheduling
- **croniter** - Cron expression parsing

---

## Important Patterns

### 1. Tool Implementation
```python
class MyTool(Tool):
    @property
    def name(self) -> str:
        return "my_tool"

    @property
    def parameters(self) -> dict:
        return {"type": "object", "properties": {...}, "required": [...]}

    async def execute(self, **kwargs) -> str:
        # Do work
        return "result"
```

### 2. Message Processing Loop
```python
while iteration < max_iterations:
    response = await provider.chat(messages, tools)
    if response.has_tool_calls:
        # Add tool calls to messages
        # Execute tools
        # Add results to messages
        # Continue loop
    else:
        # No more tools, done
        break
```

### 3. Session/History Management
```python
session = sessions.get_or_create(channel:chat_id)
history = session.get_history()  # Last 50 messages
messages = build_messages(system_prompt, history, current_msg)
# ... process ...
session.add_message("user", content)
session.add_message("assistant", response)
sessions.save(session)
```

### 4. Channel Implementation
```python
class MyChannel(BaseChannel):
    async def start(self):
        # Connect to platform
        # Listen for messages
        # Call _handle_message()

    async def send(self, msg: OutboundMessage):
        # Send to platform
```

### 5. Access Control
```python
if not channel.is_allowed(sender_id):
    # Deny access
    return

# allow_from list: empty = allow all, non-empty = whitelist
```

---

## Command Reference

### One-Time Setup
```bash
nanobot onboard
# Creates config.json and workspace directory
```

### Single Message
```bash
nanobot agent -m "What is 2+2?"
# Processes message and prints response
```

### Interactive Chat
```bash
nanobot agent
# Reads from stdin, loops until exit
```

### Multi-Channel Gateway
```bash
nanobot gateway
# Starts all enabled channels (Telegram, Discord, etc)
# Agent processes messages continuously
```

### Scheduled Tasks
```bash
nanobot cron add --name "daily" --message "Hello" --cron "0 9 * * *"
nanobot cron list
nanobot cron remove <job_id>
```

### System Status
```bash
nanobot status
# Shows configuration and channel status
```

---

## Development Workflow

### To Add a New Tool
1. Create `nanobot/agent/tools/my_tool.py`
2. Inherit from `Tool` ABC
3. Implement `name`, `description`, `parameters`, `execute()`
4. Register in `AgentLoop._register_default_tools()`
5. Test parameter validation

### To Add a New Channel
1. Create `nanobot/channels/my_channel.py`
2. Inherit from `BaseChannel`
3. Implement `start()`, `stop()`, `send()`
4. Call `_handle_message()` for incoming messages
5. Add config schema in `config/schema.py`
6. Register in `ChannelManager`

### To Add a New Provider
1. Create `nanobot/providers/my_provider.py`
2. Inherit from `LLMProvider`
3. Implement `chat()` and `get_default_model()`
4. Configure environment/auth
5. Parse response into `LLMResponse` format

---

## Testing

### Unit Tests
```bash
pytest tests/test_tool_validation.py
```

### Test Structure
```
tests/
  test_tool_validation.py     - Tool parameter validation
  # Add more as needed
```

---

## Performance Notes

### Optimization Points
- **Message bus**: Queue-based, O(1) operations
- **Tool execution**: Async where possible
- **Session history**: Limited to last 50 messages by default
- **LLM context**: System prompt + history + current message
- **Max iterations**: 20 by default (prevents infinite loops)

### Bottlenecks
- LLM API calls (network latency)
- Large file operations (agent can read/write large files)
- Shell command execution (depends on command)
- Web fetching (network + parsing)

---

## Security Considerations

### Access Control
- `allowFrom` list per channel (whitelist of user IDs)
- Empty list = allow all users
- Non-empty list = only listed users can interact

### Command Safety
- `ExecTool` has deny patterns blocking:
  - `rm -rf`, `rmdir /s` (destructive)
  - `format`, `mkfs` (disk operations)
  - `shutdown`, `reboot` (system power)
  - `dd`, fork bombs (dangerous)

### Workspace Sandboxing
- `restrictToWorkspace: true` limits all file ops to workspace
- Prevents path traversal
- Shell commands run in workspace directory

---

## Troubleshooting

### "Tool 'X' not found"
- Tool not registered in `AgentLoop._register_default_tools()`
- Check tool name matches exactly

### "Invalid parameters"
- Tool parameter validation failed
- Check JSON schema matches provided params
- Verify all `required` fields are present

### "Access denied"
- Sender ID not in `allowFrom` list for channel
- Add user ID to config under `channels.CHANNEL.allowFrom`

### Sessions not saving
- Check `~/.nanobot/sessions/` directory exists
- Verify write permissions
- Look for errors in logs

### LLM not responding
- Check API key is valid
- Verify model name is correct
- Check internet connection
- Check API rate limits

---

## Python Version & Dependencies

- **Python**: 3.11+ required
- **Package manager**: pip, pip-tools, or uv
- **Install**: `pip install -e .` (from source) or `pip install nanobot-ai`
- **Key deps**: litellm, pydantic, typer, python-telegram-bot, websockets

---

## File Size Reference

| Component | Lines | Files |
|-----------|-------|-------|
| Agent | ~1500 | 8 |
| Tools | ~700 | 9 |
| Channels | ~1000 | 7 |
| Providers | ~300 | 3 |
| Config | ~150 | 2 |
| Bus | ~150 | 2 |
| CLI | ~400 | 1 |
| Session | ~200 | 1 |
| Cron | ~200 | 2 |
| Utils | ~50 | 1 |
| **TOTAL** | **~4,747** | **46** |

---

## Key Architectural Decisions

### Message Bus
- **Why**: Decouples channels from agent, allows scaling
- **Trade-off**: Extra queue layer adds minor latency

### Tool Registry Pattern
- **Why**: Dynamic tool management, easy to extend
- **Trade-off**: Lookup by name adds complexity

### Session-based History
- **Why**: Per-user context, persistent across restarts
- **Trade-off**: JSONL files instead of structured DB

### Async Throughout
- **Why**: Handle multiple channels concurrently
- **Trade-off**: Async/await syntax complexity

### Bootstrap Files
- **Why**: Customizable agent personality per workspace
- **Trade-off**: Multiple small files instead of single config

---

## Next Steps for Understanding

1. **Read the README**: `README.md` for overview
2. **Understand the loop**: `nanobot/agent/loop.py` is the heart
3. **See tool examples**: `nanobot/agent/tools/filesystem.py`
4. **Check a channel**: `nanobot/channels/telegram.py`
5. **Review config**: `nanobot/config/schema.py`
6. **Try it locally**: `nanobot onboard` then `nanobot agent -m "test"`

---

## License
MIT - See LICENSE file
