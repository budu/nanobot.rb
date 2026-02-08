# Nanobot Detailed Architecture & Code Examples

This document provides detailed architectural insights and code examples for the Ruby port.

---

## 1. Agent Loop - Core Processing Engine

### Python Implementation (nanobot/agent/loop.py)

The agent loop is the heart of the system. It processes messages in a loop:

```python
class AgentLoop:
    async def _process_message(self, msg: InboundMessage) -> OutboundMessage | None:
        # Get or create session for this user
        session = self.sessions.get_or_create(msg.session_key)

        # Build context: system prompt + history + current message
        messages = self.context.build_messages(
            history=session.get_history(),
            current_message=msg.content,
            channel=msg.channel,
            chat_id=msg.chat_id,
        )

        # AGENT LOOP - call LLM and execute tools
        iteration = 0
        final_content = None

        while iteration < self.max_iterations:
            iteration += 1

            # Call LLM with current messages and available tools
            response = await self.provider.chat(
                messages=messages,
                tools=self.tools.get_definitions(),
                model=self.model
            )

            # Check if LLM wants to call tools
            if response.has_tool_calls:
                # Add assistant message with tool calls
                tool_call_dicts = [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.name,
                            "arguments": json.dumps(tc.arguments)
                        }
                    }
                    for tc in response.tool_calls
                ]
                messages = self.context.add_assistant_message(
                    messages, response.content, tool_call_dicts
                )

                # Execute each tool call
                for tool_call in response.tool_calls:
                    result = await self.tools.execute(tool_call.name, tool_call.arguments)
                    messages = self.context.add_tool_result(
                        messages, tool_call.id, tool_call.name, result
                    )

                # Continue loop to call LLM again with tool results
            else:
                # No tool calls - we have the final response
                final_content = response.content
                break

        # Save to session history
        session.add_message("user", msg.content)
        session.add_message("assistant", final_content)
        self.sessions.save(session)

        # Return response
        return OutboundMessage(
            channel=msg.channel,
            chat_id=msg.chat_id,
            content=final_content
        )
```

### Key Concepts for Ruby Port:

1. **Session Management**: Per-user conversation history
2. **Tool Execution Loop**: Keep calling LLM until no tool calls
3. **Message Accumulation**: Add tool results to messages between iterations
4. **Iteration Limit**: Prevent infinite loops (max 20)

### Ruby Implementation Strategy:

```ruby
class AgentLoop
  def process_message(msg)
    # Get or create session
    session = sessions.get_or_create(msg.session_key)

    # Build context
    messages = context.build_messages(
      history: session.get_history,
      current_message: msg.content,
      channel: msg.channel,
      chat_id: msg.chat_id
    )

    # Agent loop
    final_content = nil
    iteration = 0

    while iteration < max_iterations
      iteration += 1

      # Call LLM
      response = provider.chat(
        messages: messages,
        tools: tools.get_definitions,
        model: model
      )

      if response.tool_calls.any?
        # Add assistant message
        messages << {
          role: "assistant",
          content: response.content,
          tool_calls: response.tool_calls.map { |tc| ... }
        }

        # Execute tools
        response.tool_calls.each do |tool_call|
          result = tools.execute(tool_call.name, tool_call.arguments)
          messages << {
            role: "tool",
            tool_call_id: tool_call.id,
            name: tool_call.name,
            content: result
          }
        end
      else
        # Done
        final_content = response.content
        break
      end
    end

    # Save and return
    session.add_message("user", msg.content)
    session.add_message("assistant", final_content)
    sessions.save(session)

    OutboundMessage.new(
      channel: msg.channel,
      chat_id: msg.chat_id,
      content: final_content
    )
  end
end
```

---

## 2. Message Bus - Decoupling Architecture

### Python Implementation (nanobot/bus/queue.py)

```python
class MessageBus:
    def __init__(self):
        # Two queues for bidirectional communication
        self.inbound: asyncio.Queue[InboundMessage] = asyncio.Queue()
        self.outbound: asyncio.Queue[OutboundMessage] = asyncio.Queue()

        # Channels subscribe to outbound messages
        self._outbound_subscribers: dict[str, list[Callable]] = {}

    async def publish_inbound(self, msg: InboundMessage) -> None:
        """Channels publish incoming messages"""
        await self.inbound.put(msg)

    async def consume_inbound(self) -> InboundMessage:
        """Agent loop consumes messages from channels"""
        return await self.inbound.get()

    async def publish_outbound(self, msg: OutboundMessage) -> None:
        """Agent loop publishes outgoing messages"""
        await self.outbound.put(msg)

    async def dispatch_outbound(self) -> None:
        """Background task dispatches messages to subscribed channels"""
        while self._running:
            try:
                msg = await asyncio.wait_for(self.outbound.get(), timeout=1.0)

                # Get subscribers for this channel
                subscribers = self._outbound_subscribers.get(msg.channel, [])

                # Call each subscriber
                for callback in subscribers:
                    await callback(msg)
            except asyncio.TimeoutError:
                continue

    def subscribe_outbound(self, channel: str, callback: Callable) -> None:
        """Channels subscribe to outbound messages for their channel"""
        if channel not in self._outbound_subscribers:
            self._outbound_subscribers[channel] = []
        self._outbound_subscribers[channel].append(callback)
```

### Architecture Diagram:

```
Telegram Channel              Discord Channel
        ↓                             ↓
    msg.publish_inbound()        msg.publish_inbound()
        ↓                             ↓
        └─────────────┬───────────────┘
                      ↓
            MessageBus.inbound
            (asyncio.Queue)
                      ↓
            AgentLoop.run():
            consume_inbound()
                      ↓
            _process_message()
                      ↓
            publish_outbound()
                      ↓
            MessageBus.outbound
            (asyncio.Queue)
                      ↓
        dispatch_outbound()
            (background task)
                      ↓
        ┌─────────────┴───────────────┐
        ↓                             ↓
  telegram.send()              discord.send()
        ↓                             ↓
    Telegram API              Discord API
```

### Ruby Implementation Strategy:

```ruby
class MessageBus
  def initialize
    @inbound_queue = Queue.new
    @outbound_queue = Queue.new
    @outbound_subscribers = Hash.new { |h, k| h[k] = [] }
  end

  def publish_inbound(msg)
    @inbound_queue.push(msg)
  end

  def consume_inbound(timeout: nil)
    if timeout
      @inbound_queue.pop(true) rescue ThreadError => nil
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
      loop do
        msg = @outbound_queue.pop

        subscribers = @outbound_subscribers[msg.channel]
        subscribers.each { |cb| cb.call(msg) }
      end
    end
  end
end
```

---

## 3. Tool System - Extensible Capabilities

### Python Tool Base Class

```python
class Tool(ABC):
    """Abstract base for all tools"""

    @property
    @abstractmethod
    def name(self) -> str:
        """e.g., "read_file", "exec", "web_search"""
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """Describes what the tool does"""
        pass

    @property
    @abstractmethod
    def parameters(self) -> dict[str, Any]:
        """JSON Schema for parameters"""
        pass

    @abstractmethod
    async def execute(self, **kwargs: Any) -> str:
        """Execute the tool and return result string"""
        pass

    def to_schema(self) -> dict[str, Any]:
        """Convert to OpenAI function schema format"""
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            }
        }
```

### Example Tool: ReadFileTool

```python
class ReadFileTool(Tool):
    def __init__(self, allowed_dir: Path | None = None):
        self.allowed_dir = allowed_dir

    @property
    def name(self) -> str:
        return "read_file"

    @property
    def description(self) -> str:
        return "Read the contents of a file"

    @property
    def parameters(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Path to file to read"
                }
            },
            "required": ["path"]
        }

    async def execute(self, path: str, **kwargs: Any) -> str:
        try:
            file_path = Path(path).resolve()

            # Security: check if within allowed directory
            if self.allowed_dir:
                if not str(file_path).startswith(str(self.allowed_dir)):
                    return f"Error: Path {path} is outside allowed directory"

            if not file_path.exists():
                return f"Error: File not found: {path}"

            if not file_path.is_file():
                return f"Error: Not a file: {path}"

            return file_path.read_text(encoding="utf-8")
        except Exception as e:
            return f"Error reading file: {str(e)}"
```

### Tool Registry

```python
class ToolRegistry:
    def __init__(self):
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool) -> None:
        self._tools[tool.name] = tool

    def get_definitions(self) -> list[dict[str, Any]]:
        """Export all tools as OpenAI function schemas"""
        return [tool.to_schema() for tool in self._tools.values()]

    async def execute(self, name: str, params: dict[str, Any]) -> str:
        """Execute a tool by name"""
        tool = self._tools.get(name)
        if not tool:
            return f"Error: Tool '{name}' not found"

        try:
            # Validate parameters
            errors = tool.validate_params(params)
            if errors:
                return f"Error: Invalid parameters: {'; '.join(errors)}"

            # Execute
            return await tool.execute(**params)
        except Exception as e:
            return f"Error executing {name}: {str(e)}"
```

### Ruby Implementation Strategy:

```ruby
# Base tool class
class Tool
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
end

# Example tool
class ReadFileTool < Tool
  def initialize(allowed_dir: nil)
    @allowed_dir = allowed_dir
  end

  def name
    "read_file"
  end

  def description
    "Read the contents of a file"
  end

  def parameters
    {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Path to file to read"
        }
      },
      required: ["path"]
    }
  end

  def execute(path:, **kwargs)
    begin
      file_path = File.expand_path(path)

      # Security check
      if @allowed_dir && !file_path.start_with?(@allowed_dir)
        return "Error: Path #{path} is outside allowed directory"
      end

      raise "File not found: #{path}" unless File.exist?(file_path)
      raise "Not a file: #{path}" unless File.file?(file_path)

      File.read(file_path)
    rescue => e
      "Error reading file: #{e.message}"
    end
  end
end

# Registry
class ToolRegistry
  def initialize
    @tools = {}
  end

  def register(tool)
    @tools[tool.name] = tool
  end

  def get_definitions
    @tools.values.map(&:to_schema)
  end

  def execute(name, params)
    tool = @tools[name]
    return "Error: Tool '#{name}' not found" unless tool

    begin
      tool.execute(**params)
    rescue => e
      "Error executing #{name}: #{e.message}"
    end
  end
end
```

---

## 4. Context Builder - Prompt Assembly

### Python Implementation

```python
class ContextBuilder:
    def build_system_prompt(self) -> str:
        """Build complete system prompt from multiple sources"""
        parts = []

        # 1. Core identity
        parts.append(self._get_identity())

        # 2. Bootstrap files from workspace
        bootstrap = self._load_bootstrap_files()
        if bootstrap:
            parts.append(bootstrap)

        # 3. Memory context
        memory = self.memory.get_memory_context()
        if memory:
            parts.append(f"# Memory\n\n{memory}")

        # 4. Skills
        always_skills = self.skills.get_always_skills()
        if always_skills:
            always_content = self.skills.load_skills_for_context(always_skills)
            parts.append(f"# Active Skills\n\n{always_content}")

        # 5. Skills summary
        skills_summary = self.skills.build_skills_summary()
        if skills_summary:
            parts.append(f"# Skills\n\n{skills_summary}")

        return "\n\n---\n\n".join(parts)

    def _get_identity(self) -> str:
        """Core identity and runtime info"""
        return f"""# nanobot
You are nanobot, a helpful AI assistant.

Current Time: {datetime.now().strftime("%Y-%m-%d %H:%M")}
Runtime: {platform.system()} {platform.machine()}, Python {platform.python_version()}
Workspace: {self.workspace}

## Tools Available
- read_file / write_file / edit_file / list_dir - File operations
- exec - Execute shell commands
- web_search / web_fetch - Web browsing
- message - Send messages to channels
- spawn - Spawn background subagents
- cron - Manage scheduled tasks

IMPORTANT: For normal conversation, respond directly with text.
Only use the 'message' tool for sending to specific chat channels.
"""

    def _load_bootstrap_files(self) -> str:
        """Load AGENTS.md, SOUL.md, USER.md, TOOLS.md, IDENTITY.md"""
        parts = []
        for filename in ["AGENTS.md", "SOUL.md", "USER.md", "TOOLS.md", "IDENTITY.md"]:
            filepath = self.workspace / filename
            if filepath.exists():
                content = filepath.read_text()
                parts.append(f"## {filename}\n\n{content}")
        return "\n\n".join(parts)

    def build_messages(self, history, current_message, media=None, channel=None, chat_id=None):
        """Build complete message list for LLM"""
        messages = []

        # System prompt
        system_prompt = self.build_system_prompt()
        if channel and chat_id:
            system_prompt += f"\n\nCurrent Session: channel={channel}, chat_id={chat_id}"
        messages.append({"role": "system", "content": system_prompt})

        # History
        messages.extend(history)

        # Current message (with optional images)
        user_content = self._build_user_content(current_message, media)
        messages.append({"role": "user", "content": user_content})

        return messages

    def _build_user_content(self, text, media):
        """Build user message with optional base64 images"""
        if not media:
            return text

        # Convert images to base64-encoded image URLs
        images = []
        for path in media:
            p = Path(path)
            if p.is_file():
                mime = mimetypes.guess_type(path)[0]
                if mime and mime.startswith("image/"):
                    b64 = base64.b64encode(p.read_bytes()).decode()
                    images.append({
                        "type": "image_url",
                        "image_url": {"url": f"data:{mime};base64,{b64}"}
                    })

        if not images:
            return text

        # Return mixed content (images + text)
        return images + [{"type": "text", "text": text}]
```

### Ruby Implementation Strategy:

```ruby
class ContextBuilder
  def initialize(workspace)
    @workspace = workspace
    @memory = MemoryStore.new(workspace)
    @skills = SkillsLoader.new(workspace)
  end

  def build_system_prompt
    parts = []

    # Identity
    parts << build_identity

    # Bootstrap files
    bootstrap = load_bootstrap_files
    parts << bootstrap if bootstrap

    # Memory
    memory = @memory.get_memory_context
    parts << "# Memory\n\n#{memory}" if memory

    # Skills
    always_skills = @skills.get_always_skills
    if always_skills.any?
      skills_content = @skills.load_skills_for_context(always_skills)
      parts << "# Active Skills\n\n#{skills_content}" if skills_content
    end

    skills_summary = @skills.build_skills_summary
    parts << "# Skills\n\n#{skills_summary}" if skills_summary

    parts.join("\n\n---\n\n")
  end

  def build_identity
    now = Time.now.strftime("%Y-%m-%d %H:%M")
    ruby_version = RUBY_VERSION
    platform = RUBY_PLATFORM

    <<~IDENTITY
      # nanobot
      You are nanobot, a helpful AI assistant.

      Current Time: #{now}
      Runtime: #{platform}, Ruby #{ruby_version}
      Workspace: #{@workspace}

      ## Tools Available
      - read_file / write_file / edit_file / list_dir
      - exec - Execute shell commands
      - web_search / web_fetch
      - message - Send messages to channels
      - spawn - Spawn background tasks
      - cron - Manage scheduled tasks

      IMPORTANT: For normal conversation, respond directly.
      Only use 'message' tool for specific channels.
    IDENTITY
  end

  def load_bootstrap_files
    parts = []
    ["AGENTS.md", "SOUL.md", "USER.md", "TOOLS.md", "IDENTITY.md"].each do |filename|
      filepath = File.join(@workspace, filename)
      if File.exist?(filepath)
        content = File.read(filepath)
        parts << "## #{filename}\n\n#{content}"
      end
    end
    parts.join("\n\n")
  end

  def build_messages(history:, current_message:, media: nil, channel: nil, chat_id: nil)
    messages = []

    # System prompt
    system_prompt = build_system_prompt
    system_prompt += "\n\nCurrent Session: channel=#{channel}, chat_id=#{chat_id}" if channel && chat_id
    messages << { role: "system", content: system_prompt }

    # History
    messages.concat(history)

    # Current message
    user_content = build_user_content(current_message, media)
    messages << { role: "user", content: user_content }

    messages
  end

  def build_user_content(text, media)
    return text unless media

    images = []
    media.each do |path|
      next unless File.file?(path)

      mime_type = MIME::Types.type_for(path).first&.content_type
      next unless mime_type && mime_type.start_with?("image/")

      b64 = Base64.strict_encode64(File.read(path))
      images << {
        type: "image_url",
        image_url: { url: "data:#{mime_type};base64,#{b64}" }
      }
    end

    return text if images.empty?

    images + [{ type: "text", text: text }]
  end
end
```

---

## 5. Session Management - Conversation History

### Python Implementation (nanobot/session/manager.py)

```python
@dataclass
class Session:
    """A conversation session with JSONL storage"""
    key: str
    messages: list[dict[str, Any]] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)

    def add_message(self, role: str, content: str) -> None:
        msg = {
            "role": role,
            "content": content,
            "timestamp": datetime.now().isoformat()
        }
        self.messages.append(msg)
        self.updated_at = datetime.now()

    def get_history(self, max_messages: int = 50) -> list[dict]:
        """Get recent messages in LLM format"""
        recent = self.messages[-max_messages:] if len(self.messages) > max_messages else self.messages
        return [{"role": m["role"], "content": m["content"]} for m in recent]

class SessionManager:
    def __init__(self, workspace: Path):
        self.workspace = workspace
        self.sessions_dir = ensure_dir(Path.home() / ".nanobot" / "sessions")
        self._cache: dict[str, Session] = {}

    def get_or_create(self, key: str) -> Session:
        """Get cached session or load from disk"""
        if key in self._cache:
            return self._cache[key]

        session = self._load(key)
        if session is None:
            session = Session(key=key)

        self._cache[key] = session
        return session

    def _load(self, key: str) -> Session | None:
        """Load session from JSONL file"""
        path = self.sessions_dir / f"{safe_filename(key)}.jsonl"

        if not path.exists():
            return None

        messages = []
        metadata = {}

        with open(path) as f:
            for line in f:
                if not line.strip():
                    continue
                data = json.loads(line)
                if data.get("_type") == "metadata":
                    metadata = data.get("metadata", {})
                else:
                    messages.append(data)

        return Session(key=key, messages=messages, metadata=metadata)

    def save(self, session: Session) -> None:
        """Save session to JSONL file"""
        path = self.sessions_dir / f"{safe_filename(session.key)}.jsonl"

        with open(path, "w") as f:
            # Metadata line
            metadata_line = {
                "_type": "metadata",
                "created_at": session.created_at.isoformat(),
                "updated_at": session.updated_at.isoformat(),
                "metadata": session.metadata
            }
            f.write(json.dumps(metadata_line) + "\n")

            # Message lines
            for msg in session.messages:
                f.write(json.dumps(msg) + "\n")

        self._cache[session.key] = session
```

### JSONL Format Example:

```jsonl
{"_type": "metadata", "created_at": "2024-02-07T10:30:00", "updated_at": "2024-02-07T10:35:00", "metadata": {}}
{"role": "user", "content": "What is 2+2?", "timestamp": "2024-02-07T10:30:15"}
{"role": "assistant", "content": "2+2 equals 4.", "timestamp": "2024-02-07T10:30:20"}
{"role": "user", "content": "And 3+3?", "timestamp": "2024-02-07T10:30:30"}
{"role": "assistant", "content": "3+3 equals 6.", "timestamp": "2024-02-07T10:30:35"}
```

### Ruby Implementation Strategy:

```ruby
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
    msg = {
      role: role,
      content: content,
      timestamp: Time.now.iso8601
    }
    @messages << msg
    @updated_at = Time.now
  end

  def get_history(max_messages: 50)
    recent = @messages.length > max_messages ? @messages[-max_messages..-1] : @messages
    recent.map { |m| { role: m[:role], content: m[:content] } }
  end
end

class SessionManager
  def initialize(workspace)
    @workspace = workspace
    @sessions_dir = File.expand_path("~/.nanobot/sessions")
    FileUtils.mkdir_p(@sessions_dir) unless Dir.exist?(@sessions_dir)
    @cache = {}
  end

  def get_or_create(key)
    return @cache[key] if @cache[key]

    session = load(key) || Session.new(key)
    @cache[key] = session
    session
  end

  def load(key)
    path = File.join(@sessions_dir, "#{safe_filename(key)}.jsonl")
    return nil unless File.exist?(path)

    messages = []
    metadata = {}
    created_at = nil

    File.foreach(path) do |line|
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

  def save(session)
    path = File.join(@sessions_dir, "#{safe_filename(session.key)}.jsonl")

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

  private

  def safe_filename(str)
    str.gsub(/[^a-zA-Z0-9._-]/, "_")
  end
end
```

---

## 6. Channel Implementation Pattern

### Python Base Channel

```python
class BaseChannel(ABC):
    name: str = "base"

    def __init__(self, config: Any, bus: MessageBus):
        self.config = config
        self.bus = bus
        self._running = False

    @abstractmethod
    async def start(self) -> None:
        """Start listening for messages"""
        pass

    @abstractmethod
    async def stop(self) -> None:
        """Stop and clean up"""
        pass

    @abstractmethod
    async def send(self, msg: OutboundMessage) -> None:
        """Send message to platform"""
        pass

    def is_allowed(self, sender_id: str) -> bool:
        """Check if sender is in allowFrom list"""
        allow_list = getattr(self.config, "allow_from", [])
        if not allow_list:
            return True  # No list = allow all

        sender_str = str(sender_id)
        return sender_str in allow_list

    async def _handle_message(
        self,
        sender_id: str,
        chat_id: str,
        content: str,
        media: list[str] | None = None,
        metadata: dict[str, Any] | None = None
    ) -> None:
        """Process incoming message from platform"""
        if not self.is_allowed(sender_id):
            logger.warning(f"Access denied for {sender_id}")
            return

        msg = InboundMessage(
            channel=self.name,
            sender_id=str(sender_id),
            chat_id=str(chat_id),
            content=content,
            media=media or [],
            metadata=metadata or {}
        )

        await self.bus.publish_inbound(msg)
```

### Example: Telegram Channel

```python
class TelegramChannel(BaseChannel):
    name = "telegram"

    def __init__(self, config: TelegramConfig, bus: MessageBus):
        super().__init__(config, bus)
        self.bot = Application.builder().token(config.token).build()

        # Add message handler
        self.bot.add_handler(MessageHandler(filters.TEXT, self._on_message))

    async def start(self) -> None:
        self._running = True
        await self.bot.run_polling()

    async def stop(self) -> None:
        self._running = False
        await self.bot.stop()

    async def _on_message(self, update, context) -> None:
        """Handle incoming Telegram message"""
        msg = update.message
        await self._handle_message(
            sender_id=msg.from_user.id,
            chat_id=msg.chat_id,
            content=msg.text or "",
        )

    async def send(self, msg: OutboundMessage) -> None:
        """Send message to Telegram"""
        await self.bot.bot.send_message(
            chat_id=msg.chat_id,
            text=msg.content
        )
```

### Ruby Implementation Strategy:

```ruby
class BaseChannel
  attr_reader :config, :bus

  def initialize(config, bus)
    @config = config
    @bus = bus
    @running = false
  end

  def start
    raise NotImplementedError
  end

  def stop
    raise NotImplementedError
  end

  def send(msg)
    raise NotImplementedError
  end

  def is_allowed?(sender_id)
    allow_list = config.allow_from || []
    return true if allow_list.empty?

    allow_list.include?(sender_id.to_s)
  end

  protected

  def handle_message(sender_id:, chat_id:, content:, media: nil, metadata: nil)
    unless is_allowed?(sender_id)
      puts "Access denied for #{sender_id}"
      return
    end

    msg = InboundMessage.new(
      channel: self.class.name.demodulize.downcase,
      sender_id: sender_id.to_s,
      chat_id: chat_id.to_s,
      content: content,
      media: media || [],
      metadata: metadata || {}
    )

    @bus.publish_inbound(msg)
  end
end

# Telegram example
class TelegramChannel < BaseChannel
  def initialize(config, bus)
    super
    @client = Telegram::Bot::Client.new(config.token)
  end

  def start
    @running = true
    loop do
      @client.listen do |message|
        handle_message(
          sender_id: message.from.id,
          chat_id: message.chat.id,
          content: message.text || ""
        )
      end
    end
  end

  def stop
    @running = false
  end

  def send(msg)
    @client.api.send_message(
      chat_id: msg.chat_id,
      text: msg.content
    )
  end
end
```

---

## 7. LLM Provider Abstraction

### Python Base Provider

```python
@dataclass
class LLMResponse:
    """Response from LLM"""
    content: str | None
    tool_calls: list[ToolCallRequest] = field(default_factory=list)
    finish_reason: str = "stop"
    usage: dict[str, int] = field(default_factory=dict)

    @property
    def has_tool_calls(self) -> bool:
        return len(self.tool_calls) > 0

class LLMProvider(ABC):
    @abstractmethod
    async def chat(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        model: str | None = None,
        max_tokens: int = 4096,
        temperature: float = 0.7,
    ) -> LLMResponse:
        pass

    @abstractmethod
    def get_default_model(self) -> str:
        pass
```

### LiteLLM Provider (Multi-provider support)

```python
class LiteLLMProvider(LLMProvider):
    def __init__(self, api_key: str | None = None, api_base: str | None = None,
                 default_model: str = "anthropic/claude-opus-4-5"):
        self.api_key = api_key
        self.api_base = api_base
        self.default_model = default_model

        # Configure environment based on provider
        if api_key:
            if api_key.startswith("sk-or-"):
                os.environ["OPENROUTER_API_KEY"] = api_key
            elif "deepseek" in default_model:
                os.environ["DEEPSEEK_API_KEY"] = api_key
            # ... etc

    async def chat(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        model: str | None = None,
        max_tokens: int = 4096,
        temperature: float = 0.7,
    ) -> LLMResponse:
        model = model or self.default_model

        response = await acompletion(
            model=model,
            messages=messages,
            tools=tools,
            max_tokens=max_tokens,
            temperature=temperature,
        )

        # Extract content and tool calls from response
        content = response.choices[0].message.content
        tool_calls = []

        if hasattr(response.choices[0].message, 'tool_calls'):
            for tc in response.choices[0].message.tool_calls:
                tool_calls.append(ToolCallRequest(
                    id=tc.id,
                    name=tc.function.name,
                    arguments=json.loads(tc.function.arguments)
                ))

        return LLMResponse(
            content=content,
            tool_calls=tool_calls,
            finish_reason=response.choices[0].finish_reason,
            usage=dict(response.usage) if response.usage else {}
        )

    def get_default_model(self) -> str:
        return self.default_model
```

### Ruby Implementation Strategy:

```ruby
LLMResponse = Struct.new(:content, :tool_calls, :finish_reason, :usage) do
  def has_tool_calls?
    tool_calls.any?
  end
end

ToolCallRequest = Struct.new(:id, :name, :arguments)

class LLMProvider
  def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
    raise NotImplementedError
  end

  def get_default_model
    raise NotImplementedError
  end
end

class LiteLLMProvider < LLMProvider
  def initialize(api_key: nil, api_base: nil, default_model: "anthropic/claude-opus-4-5")
    @api_key = api_key
    @api_base = api_base
    @default_model = default_model

    # Configure environment
    if api_key
      if api_key.start_with?("sk-or-")
        ENV["OPENROUTER_API_KEY"] = api_key
      elsif default_model.include?("deepseek")
        ENV["DEEPSEEK_API_KEY"] = api_key
      # ... etc
      end
    end
  end

  def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
    model ||= @default_model

    payload = {
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      temperature: temperature
    }
    payload[:tools] = tools if tools

    response = HTTPClient.post(
      url: "https://api.openrouter.ai/api/v1/chat/completions",
      headers: {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type" => "application/json"
      },
      body: JSON.generate(payload)
    )

    data = JSON.parse(response.body)

    content = data["choices"][0]["message"]["content"]
    tool_calls = []

    if data["choices"][0]["message"]["tool_calls"]
      data["choices"][0]["message"]["tool_calls"].each do |tc|
        tool_calls << ToolCallRequest.new(
          tc["id"],
          tc["function"]["name"],
          JSON.parse(tc["function"]["arguments"])
        )
      end
    end

    LLMResponse.new(
      content,
      tool_calls,
      data["choices"][0]["finish_reason"],
      data["usage"]
    )
  end

  def get_default_model
    @default_model
  end
end
```

---

## 8. Execution Flow Sequence Diagram

### Simple Conversation Flow

```
User
 │
 └─→ "What is nanobot?"
     │
     └─→ Telegram Channel
         │
         └─→ _handle_message()
             │
             ├─→ is_allowed(user_id)?
             │   └─ Yes
             │
             └─→ InboundMessage(
                   channel="telegram",
                   sender_id="123456",
                   chat_id="789",
                   content="What is nanobot?"
                 )
                 │
                 └─→ MessageBus.publish_inbound()
                     │
                     └─→ MessageBus.inbound.put(msg)
                         │
                         └─→ AgentLoop.run()
                             │
                             └─→ consume_inbound()
                                 │
                                 └─→ _process_message(msg)
                                     │
                                     ├─→ SessionManager.get_or_create("telegram:789")
                                     │
                                     ├─→ ContextBuilder.build_messages(
                                     │     history=[],
                                     │     current_message="What is nanobot?"
                                     │   )
                                     │   Result: [
                                     │     {role: "system", content: "# nanobot\n..."},
                                     │     {role: "user", content: "What is nanobot?"}
                                     │   ]
                                     │
                                     ├─→ AGENT LOOP (iteration 1):
                                     │   │
                                     │   ├─→ LLMProvider.chat(
                                     │   │     messages=[...],
                                     │   │     tools=[read_file, exec, ...]
                                     │   │   )
                                     │   │
                                     │   └─→ LLMResponse:
                                     │       content="nanobot is..."
                                     │       tool_calls=[]
                                     │       finish_reason="end_turn"
                                     │
                                     ├─→ No tool_calls → final_content="nanobot is..."
                                     │
                                     ├─→ Session.add_message("user", ...)
                                     ├─→ Session.add_message("assistant", ...)
                                     ├─→ SessionManager.save(session)
                                     │
                                     └─→ OutboundMessage(
                                           channel="telegram",
                                           chat_id="789",
                                           content="nanobot is..."
                                         )
                                         │
                                         └─→ MessageBus.publish_outbound()
                                             │
                                             └─→ MessageBus.dispatch_outbound()
                                                 │
                                                 └─→ TelegramChannel.send()
                                                     │
                                                     └─→ Telegram Bot API
                                                         │
                                                         └─→ User receives response
```

### With Tool Execution

```
User
 │
 └─→ "Read the file /path/to/file.txt"
     │
     └─→ ... (same setup as above) ...
         │
         └─→ AGENT LOOP (iteration 1):
             │
             ├─→ LLMProvider.chat()
             │
             └─→ LLMResponse:
                 content="I'll read that file for you"
                 tool_calls=[
                   {id: "call_1", name: "read_file", arguments: {path: "/path/to/file.txt"}}
                 ]
                 finish_reason="tool_calls"
             │
             ├─→ Add assistant message with tool_calls
             │
             ├─→ FOR each tool_call:
             │   │
             │   └─→ ToolRegistry.execute("read_file", {path: "/path/to/file.txt"})
             │       │
             │       ├─→ ReadFileTool.validate_params()
             │       │   └─ Valid
             │       │
             │       └─→ ReadFileTool.execute(path="/path/to/file.txt")
             │           │
             │           └─→ File.read() → "file contents..."
             │
             │   └─→ Add tool result message:
             │       {
             │         role: "tool",
             │         tool_call_id: "call_1",
             │         name: "read_file",
             │         content: "file contents..."
             │       }
             │
             ├─→ has_tool_calls? YES → continue loop
             │
             └─→ AGENT LOOP (iteration 2):
                 │
                 ├─→ LLMProvider.chat(
                       messages=[system, user, assistant_with_tools, tool_result]
                     )
                 │
                 └─→ LLMResponse:
                     content="The file contains: file contents..."
                     tool_calls=[]
                     finish_reason="end_turn"
                 │
                 ├─→ No tool_calls → break
                 │
                 └─→ final_content="The file contains:..."
                     │
                     └─→ (save, send response)
```

---

## Summary Table: Python → Ruby Mapping

| Concept | Python | Ruby Strategy |
|---------|--------|---------------|
| Async/await | asyncio | Thread, Fiber, or Async gem |
| Message Queue | asyncio.Queue | Queue (threadsafe) |
| Abstract Base | ABC + @abstractmethod | Module mixins or inheritance |
| Dataclasses | @dataclass | Struct or OpenStruct |
| Type hints | Type annotations | YARD or just code |
| Validation | Pydantic | dry-validation or custom |
| JSON Parsing | json module | JSON library |
| WebSocket | websockets lib | websocket-eventmachine |
| HTTP client | httpx (async) | Faraday or Net::HTTP |
| CLI | Typer | Thor or CLI gem |
| Logging | loguru | Logger or Serilog gem |
| Config file | JSON + Pydantic | JSON + dry-validation |
| Date/time | datetime | Time, Date |
| Path handling | pathlib.Path | File, Pathname |
| Subprocess | asyncio.subprocess | Process or Open3 |
| Environment | os.environ | ENV hash |
