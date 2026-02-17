# Goals

What Nanobot.rb aims to be and what it deliberately stays away from.

## Vision

A minimal, complete personal AI assistant framework. Small enough to read in an
afternoon, functional enough to use every day, clean enough to fork and build on.

Nanobot.rb is a starting point, not a destination. It provides the essential
building blocks -- an agent loop, tools, channels, memory, sessions -- and
stops there. Major new features belong in forks, not in this codebase.

## Core Principles

**Minimal and complete.** Every feature that's here earns its place. Nothing is
missing that would make the core broken, and nothing is added that isn't
essential. The current feature set is the intended feature set.

**Educational and readable.** The codebase is a reference implementation of a
personal AI assistant. Every module should be understandable by reading a single
file. Someone learning how agent loops, tool calling, or multi-channel
architectures work should be able to study this project and walk away with a
clear understanding.

**A foundation for forks.** This project is designed to be cloned and extended.
The architecture is clean and modular so that someone building a more ambitious
assistant can start here and add what they need without fighting the codebase.

**Self-hosted and private.** Your conversations, memory, and data stay on your
machine. No telemetry, no cloud dependencies beyond the LLM API itself.

**Secure by design.** Workspace sandboxing, dangerous command filtering, access
control, and private IP blocking are built in, not bolted on.

## What It Does

### Current Features (v0.1.0)

- Multi-provider LLM support via RubyLLM (Anthropic, OpenAI, OpenRouter, Groq, DeepSeek)
- Agent loop with tool calling (up to 20 iterations)
- Built-in tools: file operations, shell execution, web search, web fetch
- Task scheduling: one-time, recurring, and cron-based scheduled tasks
- Six channels: CLI, Slack, Telegram, Discord, Email, HTTP Gateway
- Persistent sessions via JSONL
- Dual memory system (long-term + daily notes)
- Customizable personality via bootstrap files (AGENTS.md, SOUL.md, USER.md, IDENTITY.md)
- Security: workspace sandboxing, command filtering, access control
- 97% test coverage

This is the intended scope. The project is complete as-is.

## What Belongs Here

Improvements that fit the minimal philosophy:

- **Bug fixes.** Anything that's broken should be fixed.
- **Test coverage.** Maintaining or improving coverage keeps the codebase reliable.
- **Documentation.** Clear docs make the project more useful as a reference.
- **Code quality.** Refactoring for clarity, removing dead code, improving naming.
- **Security hardening.** Better filtering, tighter sandboxing, fewer attack surfaces.
- **Reliability.** More robust error handling, edge case coverage, channel stability.
- **Performance.** Making existing features faster or more resource-efficient.

## What Belongs in a Fork

Features that expand the scope beyond a minimal core:

- Streaming responses
- Background/daemon mode
- MCP client support
- RAG and vector store integration
- Multi-agent orchestration
- Editor plugins (VS Code, Neovim)
- Voice interfaces
- Plugin ecosystems
- Web UI
- Federation

These are all worthwhile features. They just don't belong in this project.
Fork it, add what you need, build something great.

## Non-Goals

Things Nanobot.rb deliberately does not try to be:

- **A growing framework.** The feature set is intentionally frozen. This is not
  a project that ships new capabilities every release.

- **A general-purpose AI framework.** This is not LangChain. There are no
  chains, graphs, or abstract orchestration primitives.

- **A hosted service.** There is no cloud offering, no SaaS, no managed
  deployment. Users run it on their own hardware.

- **A replacement for dedicated tools.** The shell tool doesn't replace your
  terminal. The file tools don't replace your editor. The assistant augments
  your existing workflow.

- **An enterprise platform.** No RBAC, no audit logs, no multi-tenant
  isolation. This is a personal assistant, or at most a small-team tool.

## Success Metrics

How to know if Nanobot.rb is achieving its goals:

- **Time to first conversation**: under 5 minutes from clone to chatting
- **Codebase size**: stays under 5,000 lines of Ruby
- **Test coverage**: stays above 95%
- **Readability**: a new developer can understand any module in under 30 minutes
- **Forkability**: someone can clone, modify, and extend without hitting walls
- **Channel reliability**: messages are delivered and responded to consistently
- **Memory continuity**: the agent remembers context from previous sessions
- **Tool safety**: no accidental file deletions or destructive commands in normal use
- **Provider flexibility**: switching LLM providers requires changing one config value
