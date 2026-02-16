# Use Cases

How Nanobot.rb is used and who it's for.

## Who Uses This

### Developers

The primary audience. They want an AI assistant that lives in their terminal
and chat apps. They value:

- Control over which LLM provider and model they use
- Self-hosted operation where data stays on their machine
- Customizable personality and behavior via text files, not GUIs
- A codebase small enough to read, understand, and modify

### Small Teams

A team deploys a shared assistant in Slack or Discord. The bot handles common
questions, automates repetitive tasks, and serves as a knowledge base that
remembers context across conversations. Access control keeps it scoped to
authorized users and channels.

### Learners

People studying how AI assistant frameworks work. The codebase is a reference
implementation of agent loops, tool calling, multi-channel architectures,
session management, and memory systems. Small enough to understand end-to-end,
well-tested enough to trust as a learning resource.

### Builders

People who want a clean starting point for a more ambitious project. Fork the
repo, understand the architecture, then extend it with the features your use
case needs. The modular design makes this straightforward.

---

## What You Can Do With It

### Research and Summarization

Ask the assistant to search the web and synthesize results:

- Search the web and summarize findings
- Read documents or articles and extract key points
- Compare options with structured analysis
- Gather information for reports or decisions

**How it works**: WebSearch (Brave API) and WebFetch tools provide web access.
The agent loop handles multi-step research where the LLM decides which searches
to run and how to combine results.

### Code Assistance

Use the assistant as a coding partner with filesystem and shell access:

- Write new code from a description
- Debug issues by reading files, running tests, analyzing output
- Refactor code -- rename, restructure, extract methods
- Generate tests for existing code
- Explain unfamiliar code

**How it works**: ReadFile, WriteFile, EditFile, ListDir, and Exec tools give
the agent development capabilities. Workspace sandboxing and dangerous command
filtering prevent accidents.

### Writing and Content

Use the assistant as a writing partner:

- Draft emails, documents, and technical writing
- Edit existing text for tone, clarity, or audience
- Translate between languages
- Maintain a consistent voice defined in bootstrap files

**How it works**: AGENTS.md and SOUL.md define style and values. File tools let
the agent read source material, write drafts, and iterate. USER.md captures
author preferences.

### File and System Tasks

Let the assistant interact with your local system:

- Read, write, organize, and search files
- Run shell commands and scripts with timeout protection
- Automate multi-step workflows (fetch data, transform, save)
- Manage workspace structure

**How it works**: The Exec tool runs commands with configurable timeouts and
dangerous command blocking. File tools handle reading, writing, and editing.
Workspace sandboxing optionally restricts operations to a safe directory.

### Personal Knowledge Management

The assistant accumulates context over time:

- Remembers ongoing projects, preferences, and decisions across sessions
- Maintains daily notes automatically
- Tracks what you're working on and surfaces relevant past context
- Acts as an external memory for long-running projects

**How it works**: Long-term memory lives in MEMORY.md. Daily notes are
auto-created as YYYY-MM-DD.md files. Persistent JSONL sessions give
continuity within conversations. The context builder includes memory in
every system prompt.

### Multi-Platform Communication

Deploy the same assistant across multiple channels:

- **CLI** for quick interactions during development
- **Slack** as a team assistant in work channels
- **Telegram** or **Discord** for personal use on mobile
- **Email** for async, longer-form interactions
- **HTTP Gateway** for integration with other applications

**How it works**: Six channel implementations share a single agent loop and
session manager. Each channel handles platform-specific concerns (message
splitting, threading, access control) while the core stays the same.

---

## Deployment Patterns

### Personal Workstation

The simplest setup. Run `nanobot agent` in your terminal alongside your editor.
Sessions persist in `~/.nanobot/sessions/`. The agent has access to the local
filesystem and shell. No server, no configuration beyond an API key.

### Team Bot

Deploy on a shared server or VPS with Slack or Discord enabled. Configure
access control via `allow_from` lists. The agent acts as a shared assistant
that maintains a knowledge base in its workspace.

### API Service

The HTTP Gateway exposes `/chat` and `/health` endpoints. Other applications
integrate via REST API. Bearer token authentication secures access. Useful for
embedding the assistant into internal tools or custom frontends.

### Email Assistant

The email channel polls IMAP for inbound messages and replies via SMTP. Consent
gating and auto-reply controls keep it predictable. Handles async requests
where real-time chat isn't needed.

### Multi-Channel

All channels running simultaneously. The same agent serves users across CLI,
Slack, Telegram, Discord, Email, and HTTP. Sessions stay separate per user and
channel. Bootstrap files and memory ensure consistent behavior everywhere.

---

## What's Covered and What's Not

Nanobot.rb provides the essential building blocks of a personal AI assistant.
Here's what fits the current scope and what would require a fork:

### Covered by Nanobot.rb

| Capability | Support |
|-----------|---------|
| Tool/function calling | Agent loop with up to 20 iterations |
| Multi-provider LLM | Anthropic, OpenAI, OpenRouter, Groq, DeepSeek via RubyLLM |
| Persistent sessions | JSONL-based, per user and channel |
| Long-term memory | MEMORY.md + daily notes |
| Security boundaries | Workspace sandboxing, command filtering, access control |
| CLI | Interactive and single-message modes |
| Chat platforms | Slack, Telegram, Discord |
| Email | IMAP polling + SMTP replies |
| HTTP API | REST gateway with auth |
| Customizable personality | Bootstrap files (AGENTS.md, SOUL.md, USER.md, IDENTITY.md) |
| Web access | Search (Brave API) and page fetching |

### Beyond scope (fork territory)

| Capability | Why it's a fork |
|-----------|----------------|
| Streaming responses | Changes the response model across all channels |
| Background/daemon mode | Adds process management, scheduling, and lifecycle concerns |
| MCP support | New protocol layer and tool discovery system |
| RAG / vector stores | New dependency, indexing pipeline, and retrieval logic |
| Multi-agent orchestration | Agent-to-agent communication and task delegation |
| Editor plugins | Platform-specific integrations outside the core |
| Voice interface | Audio I/O, speech-to-text, text-to-speech |
| Web UI | Frontend application on top of the gateway |
