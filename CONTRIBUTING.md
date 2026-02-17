# Contributing to Nanobot.rb

Thanks for your interest in contributing! This guide covers what you need to
get started.

## Project Philosophy

Nanobot.rb is a **minimal, educational AI assistant framework**. The current
feature set is intentionally complete -- contributions should improve what
exists, not expand the scope.

**What belongs here:**
- Bug fixes
- Test coverage improvements
- Documentation and code clarity
- Security hardening
- Performance improvements
- Reliability and error handling

**What belongs in a fork:**
- New tools, channels, or provider integrations
- Streaming, background mode, MCP, RAG, multi-agent orchestration
- Any feature that adds new capabilities beyond the current scope

If you're building something ambitious, fork the project and go for it. The
architecture is designed to be extended. See [docs/goals.md](docs/goals.md)
for more on this.

## Getting Started

### Prerequisites

- Ruby 4.0 or higher
- Git
- Bundler

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/nanobot.rb.git
   cd nanobot.rb
   ```
3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/nanobot.rb.git
   ```

## Development Setup

Install dependencies:

```bash
bundle install
```

Run the test suite:

```bash
bundle exec rspec
```

Run the linter:

```bash
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A
```

## Making Changes

### 1. Create a Branch

```bash
git checkout main
git pull upstream main
git checkout -b fix/issue-description
```

### 2. Write Code and Tests

- Follow existing patterns in the codebase
- Add tests for any changes
- Keep methods small and focused
- Prioritize clarity over cleverness

### 3. Verify Your Changes

```bash
bundle exec rspec
bundle exec rubocop
```

### Integration Tests

The test suite includes integration tests that verify the full agent loop
against real LLM responses. These use a **record/replay** approach: responses
are recorded once from a real provider, saved as fixtures, and replayed in
subsequent runs for fast, deterministic tests.

Replay mode runs automatically as part of `bundle exec rspec` using the
fixtures checked into `spec/fixtures/integration_responses/`. No API key is
needed for replay.

To **record new fixtures** against a live provider:

1. Configure an API key for the provider in `~/.nanobot/config.json`:
   ```json
   {
     "providers": {
       "anthropic": { "api_key": "sk-ant-..." }
     }
   }
   ```

2. Run with recording enabled:
   ```bash
   NANOBOT_INTEGRATION_RECORD=true \
   NANOBOT_INTEGRATION_PROVIDER=anthropic \
   NANOBOT_INTEGRATION_MODEL=claude-haiku-4-5 \
   bundle exec rspec spec/integration
   ```

This saves a timestamped fixture file in `spec/fixtures/integration_responses/`.
You can record fixtures for multiple providers and models -- replay mode
iterates over all saved fixtures automatically.

### 4. Commit with Conventional Commits

```bash
git commit -m "fix: Handle empty response in agent loop"
```

Prefixes: `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `test:`, `chore:`

Note: `feat:` should be used sparingly -- most contributions will be fixes,
refactors, docs, or test improvements.

### 5. Push and Open a PR

```bash
git push origin fix/issue-description
```

Then open a Pull Request on GitHub.

## Pull Request Guidelines

- Use a conventional commit-style title (e.g., `fix: Handle timeout in Exec tool`)
- Describe what changed and why
- Ensure all tests pass and RuboCop is clean
- Keep PRs focused -- one fix or improvement per PR
- PRs that add new features or expand scope will likely be declined -- consider
  a fork instead

## Reporting Issues

When filing a bug report, please include:

1. **Description**: What went wrong
2. **Steps to reproduce**: Minimal steps to trigger the issue
3. **Expected vs. actual behavior**
4. **Environment**: Ruby version, OS, nanobot.rb version
5. **Error output**: Stack trace or log messages

## Questions?

Open an issue or start a GitHub discussion. We're happy to help.

Thank you for contributing to Nanobot.rb!
