# Contributing to Nanobot.rb

Thanks for your interest in contributing! This guide covers what you need to get started.

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
git checkout -b feature/your-feature-name
# or: git checkout -b fix/issue-description
```

### 2. Write Code and Tests

- Follow existing patterns in the codebase
- Add tests for new functionality
- Keep methods small and focused

### 3. Verify Your Changes

```bash
bundle exec rspec
bundle exec rubocop
```

### 4. Commit with Conventional Commits

```bash
git commit -m "feat: Add weather tool support"
```

Prefixes: `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `test:`, `chore:`

### 5. Push and Open a PR

```bash
git push origin feature/your-feature-name
```

Then open a Pull Request on GitHub.

## Adding a Custom Tool

Tools extend `RubyLLM::Tool`. Place new tools in `lib/nanobot/agent/tools/` with tests in `spec/agent/tools/`.

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

## Adding a Custom Channel

Channels extend `Nanobot::Channels::BaseChannel`. Place new channels in `lib/nanobot/channels/` with tests in `spec/channels/`.

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
end
```

## Pull Request Guidelines

- Use a conventional commit-style title (e.g., `feat: Add Slack channel`)
- Describe what changed and why
- Ensure all tests pass and RuboCop is clean
- Keep PRs focused -- one feature or fix per PR

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
