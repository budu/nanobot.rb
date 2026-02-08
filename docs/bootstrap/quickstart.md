# Nanobot.rb Quick Start Guide

## Prerequisites

- Ruby 3.0 or higher
- Bundler gem
- An LLM API key (OpenAI, Anthropic, OpenRouter, etc.)

## Installation

1. **Install dependencies**:
```bash
cd /home/budu/projects/nanobot.rb
bundle install
```

2. **Initialize Nanobot**:
```bash
bundle exec bin/nanobot onboard
```

This creates:
- `~/.nanobot/config.json` - Configuration file
- `~/.nanobot/workspace/` - Workspace directory with bootstrap files
- `~/.nanobot/sessions/` - Session storage directory

3. **Add your API key**:
```bash
vim ~/.nanobot/config.json
```

Add your API key to the providers section:
```json
{
  "providers": {
    "openai": {
      "apiKey": "sk-..."
    }
  },
  "agents": {
    "defaults": {
      "model": "gpt-4o-mini"
    }
  }
}
```

## Basic Usage

### Single Message

```bash
bundle exec bin/nanobot agent -m "What is 2+2?"
```

### Interactive Chat

```bash
bundle exec bin/nanobot agent
> Hello! What can you help me with?
> What files are in the current directory?
> exit
```

### Custom Model

```bash
bundle exec bin/nanobot agent --model gpt-4o -m "Explain quantum computing"
```

### Check Status

```bash
bundle exec bin/nanobot status
```

## Customization

### Agent Personality

Edit `~/.nanobot/workspace/AGENTS.md`:
```markdown
# Agent Instructions

You are a helpful coding assistant specializing in Ruby.

## Your Capabilities
- Write and review Ruby code
- Explain Ruby concepts
- Debug Ruby applications
```

### User Profile

Edit `~/.nanobot/workspace/USER.md`:
```markdown
# User Profile

## Preferences
- Programming language: Ruby
- Code style: Rubocop compliant
- Communication: Concise and technical
```

### Memory

The agent can remember information across conversations:
- Long-term: `~/.nanobot/workspace/memory/MEMORY.md`
- Daily notes: `~/.nanobot/workspace/memory/YYYY-MM-DD.md`

## Available Tools

The agent has access to these built-in tools:

### File Operations
```
read_file(path: "file.txt")
write_file(path: "file.txt", content: "...")
edit_file(path: "file.txt", old_text: "...", new_text: "...")
list_dir(path: ".")
```

### Shell Commands
```
exec(command: "ls -la")
```

### Web Access
```
web_search(query: "Ruby best practices")
web_fetch(url: "https://example.com")
```

## Security

### Workspace Sandboxing

Enable workspace restrictions in config:
```json
{
  "tools": {
    "restrictToWorkspace": true
  }
}
```

This limits all file operations to the workspace directory.

### Access Control

For channels (when implemented), use `allowFrom`:
```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "YOUR_BOT_TOKEN",
      "allowFrom": ["123456789"]
    }
  }
}
```

Empty `allowFrom` = allow all users.
Non-empty = only listed user IDs allowed.

## Troubleshooting

### "Configuration not found"
Run `bundle exec bin/nanobot onboard` first.

### "No API key configured"
Edit `~/.nanobot/config.json` and add your API key under `providers`.

### LLM errors
- Check your API key is valid
- Verify the model name is correct
- Check your API quota/rate limits

### Tool execution errors
- Check file paths are correct
- Verify permissions for file operations
- Review shell command security restrictions

## Examples

### File Management
```bash
bundle exec bin/nanobot agent -m "Create a file called hello.txt with 'Hello World'"
```

### Code Analysis
```bash
bundle exec bin/nanobot agent -m "Read lib/nanobot.rb and explain what it does"
```

### Web Research
```bash
bundle exec bin/nanobot agent -m "Search for Ruby 3.3 new features and summarize"
```

### Shell Operations
```bash
bundle exec bin/nanobot agent -m "List all Ruby files in the current directory"
```

## Next Steps

1. **Try the examples above**
2. **Customize your agent personality** in AGENTS.md
3. **Add preferences** in USER.md
4. **Explore tool combinations** (file + web + shell)
5. **Use memory** to save important information
6. **Review the README** for advanced features

## Getting Help

- Check `IMPLEMENTATION_SUMMARY.md` for technical details
- Review `README.md` for full documentation
- Run `bundle exec bin/nanobot --help` for CLI help

## Development

Run tests:
```bash
bundle exec rspec
```

Open console:
```bash
bundle exec rake console
```

Check code style:
```bash
bundle exec rubocop
```

---

Happy chatting with Nanobot! 🤖
