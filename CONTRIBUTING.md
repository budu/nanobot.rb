# Contributing to Nanobot.rb

Thank you for your interest in contributing to Nanobot.rb! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Development Workflow](#development-workflow)
- [Testing Guidelines](#testing-guidelines)
- [Code Style](#code-style)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Feature Requests](#feature-requests)
- [Documentation](#documentation)
- [Community](#community)

## Code of Conduct

### Our Pledge

We pledge to make participation in our project a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, gender identity, level of experience, nationality, personal appearance, race, religion, or sexual identity and orientation.

### Our Standards

Examples of behavior that contributes to a positive environment:

- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards other community members

Examples of unacceptable behavior:

- Trolling, insulting/derogatory comments, and personal attacks
- Public or private harassment
- Publishing others' private information without permission
- Other conduct which could reasonably be considered inappropriate

## Getting Started

### Prerequisites

- Ruby 3.0 or higher
- Git
- Bundler
- A text editor or IDE
- Basic knowledge of Ruby and RSpec

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/nanobot.rb.git
   cd nanobot.rb
   ```
3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/nanobot.rb.git
   ```

## How to Contribute

### Types of Contributions

#### 1. Bug Fixes
- Fix existing issues
- Improve error handling
- Address edge cases
- Fix documentation errors

#### 2. Features
- Implement new tools
- Add channel integrations
- Enhance existing functionality
- Improve performance

#### 3. Documentation
- Improve README
- Add code examples
- Write tutorials
- Document APIs

#### 4. Tests
- Increase test coverage
- Add edge case tests
- Improve test performance
- Fix flaky tests

#### 5. Refactoring
- Improve code structure
- Reduce complexity
- Extract reusable components
- Optimize algorithms

## Development Setup

### 1. Install Dependencies

```bash
bundle install
```

### 2. Set Up Configuration

```bash
# Create test configuration
cp ~/.nanobot/config.json.example ~/.nanobot/config.json
# Edit with your API keys for testing
vim ~/.nanobot/config.json
```

### 3. Run Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/agent/loop_spec.rb

# Run with coverage report
bundle exec rspec
```

### 4. Check Code Style

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A
```

## Development Workflow

### 1. Create a Branch

```bash
# Update main branch
git checkout main
git pull upstream main

# Create feature branch
git checkout -b feature/your-feature-name

# Or bugfix branch
git checkout -b fix/issue-description
```

### 2. Make Changes

- Write clean, readable code
- Follow existing patterns
- Add tests for new functionality
- Update documentation

### 3. Test Your Changes

```bash
# Run tests
bundle exec rspec

# Check style
bundle exec rubocop

# Test manually
bundle exec bin/nanobot agent -m "Test message"
```

### 4. Commit Changes

```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "feat: Add Discord channel integration

- Implement Discord bot client
- Add message handling
- Include tests and documentation"
```

Follow conventional commits:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `style:` Code style
- `refactor:` Refactoring
- `test:` Tests
- `chore:` Maintenance

### 5. Push and Create PR

```bash
# Push to your fork
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

## Testing Guidelines

### Test Structure

```ruby
RSpec.describe Nanobot::Component do
  describe '#method' do
    context 'when condition' do
      it 'does something' do
        # Arrange
        component = described_class.new

        # Act
        result = component.method

        # Assert
        expect(result).to eq(expected)
      end
    end
  end
end
```

### Test Coverage

- Maintain minimum 90% code coverage
- Test happy paths and edge cases
- Include error handling tests
- Test public interfaces thoroughly

### Testing Tools

```ruby
# Unit tests for isolated components
describe MyTool do
  let(:tool) { described_class.new }

  it 'executes successfully' do
    result = tool.execute(param: 'value')
    expect(result).to eq('expected')
  end
end

# Integration tests for interactions
describe 'Agent Integration' do
  let(:agent) { build_test_agent }

  it 'processes messages with tools' do
    response = agent.process_direct("Use a tool")
    expect(response).to include('tool result')
  end
end
```

### Mock External Services

```ruby
# Mock LLM provider
before do
  allow(provider).to receive(:complete).and_return(
    double(content: 'AI response')
  )
end

# Mock file system
allow(File).to receive(:read).and_return('content')

# Mock HTTP requests
stub_request(:get, 'https://api.example.com')
  .to_return(body: '{"data": "value"}')
```

## Code Style

### Ruby Style Guide

We follow the [Ruby Style Guide](https://rubystyle.guide/) with some modifications:

```ruby
# Good: Clear method names
def calculate_total_price
  items.sum(&:price)
end

# Good: Guard clauses
def process(input)
  return nil if input.nil?
  return '' if input.empty?

  input.upcase
end

# Good: Descriptive variables
user_messages = messages.select { |m| m.from_user == user_id }

# Good: Small, focused methods
def valid_api_key?(key)
  key.present? && key.start_with?('sk-')
end
```

### RuboCop Configuration

Our `.rubocop.yml` configures:
- Line length: 120 characters
- Method length: 25 lines
- Class length: 250 lines
- RSpec example length: 35 lines

Run RuboCop before committing:
```bash
bundle exec rubocop
```

### Documentation Style

```ruby
# Document public methods
# @param message [String] the message to process
# @param options [Hash] processing options
# @option options [String] :channel the channel name
# @option options [String] :user the user identifier
# @return [String] the processed response
def process_message(message, options = {})
  # Implementation
end
```

## Pull Request Process

### Before Submitting

1. **Update your branch**:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run full test suite**:
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```

3. **Update documentation**:
   - Add/update method documentation
   - Update README if needed
   - Add examples for new features

### PR Guidelines

#### Title
- Use conventional commit format
- Be descriptive but concise
- Examples:
  - ✅ `feat: Add Slack channel integration`
  - ✅ `fix: Handle nil values in tool parameters`
  - ❌ `Updated stuff`
  - ❌ `Fixed bug`

#### Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change (fix or feature)
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] Added new tests
- [ ] Coverage maintained/improved

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No console.log/debugging code

## Related Issues
Closes #123
```

### Review Process

1. Automated checks run (tests, style)
2. Maintainer reviews code
3. Address feedback
4. Maintainer approves
5. PR is merged

### After Merging

```bash
# Update local main
git checkout main
git pull upstream main

# Delete feature branch
git branch -d feature/your-feature-name
git push origin --delete feature/your-feature-name
```

## Reporting Issues

### Bug Reports

Include:
1. **Description**: Clear problem statement
2. **Reproduction**: Steps to reproduce
3. **Expected**: What should happen
4. **Actual**: What actually happens
5. **Environment**: Ruby version, OS, etc.
6. **Logs**: Error messages, stack traces

Example:
```markdown
### Description
Agent crashes when processing empty tool response

### Steps to Reproduce
1. Configure agent with shell tool
2. Send message: "Run `echo`"
3. Agent crashes

### Expected Behavior
Agent should handle empty response

### Actual Behavior
NoMethodError: undefined method 'strip' for nil

### Environment
- Ruby 3.2.0
- macOS 14.0
- nanobot.rb version 0.1.0

### Stack Trace
```
[Include full trace]
```
```

## Feature Requests

### Proposal Template

```markdown
### Problem Statement
What problem does this solve?

### Proposed Solution
How would you solve it?

### Alternatives Considered
What other approaches exist?

### Additional Context
Screenshots, examples, etc.
```

### Feature Discussion

1. Open issue for discussion
2. Get feedback from maintainers
3. Refine proposal
4. Implement if approved
5. Submit PR

## Documentation

### Code Documentation

```ruby
# Module documentation
# Provides agent loop functionality for message processing
module Nanobot
  module Agent
    # Main agent processing loop
    #
    # @example Basic usage
    #   agent = Loop.new(provider: provider, config: config)
    #   response = agent.process_direct("Hello")
    #
    class Loop
      # Initialize a new agent loop
      #
      # @param provider [Providers::Base] LLM provider
      # @param config [Hash] configuration
      def initialize(provider:, config:)
        # Implementation
      end
    end
  end
end
```

### README Updates

- Keep README current
- Include examples
- Document breaking changes
- Update version compatibility

### Changelog

Format:
```markdown
## [0.2.0] - 2024-02-08

### Added
- Discord channel integration
- Tool timeout configuration

### Changed
- Improved error handling in agent loop

### Fixed
- Memory leak in session manager

### Removed
- Deprecated CLI options
```

## Community

### Communication Channels

- **GitHub Issues**: Bug reports, feature requests
- **GitHub Discussions**: General questions, ideas
- **Pull Requests**: Code contributions

### Getting Help

1. Check documentation
2. Search existing issues
3. Ask in discussions
4. Create new issue

### Recognition

Contributors are recognized in:
- README.md contributors section
- Release notes
- Project credits

## Specific Contribution Areas

### Adding a New Tool

1. Create tool class in `lib/nanobot/agent/tools/`
2. Implement required methods
3. Add tests in `spec/agent/tools/`
4. Update tool documentation
5. Register in default registry

Example:
```ruby
# lib/nanobot/agent/tools/weather.rb
module Nanobot::Agent::Tools
  class WeatherTool < Tool
    def name
      'get_weather'
    end

    def description
      'Get weather for a location'
    end

    def parameters
      {
        'type' => 'object',
        'properties' => {
          'location' => {
            'type' => 'string',
            'description' => 'City name'
          }
        },
        'required' => ['location']
      }
    end

    def execute(location:)
      # Implementation
    end
  end
end
```

### Adding a New Channel

1. Create channel class in `lib/nanobot/channels/`
2. Implement BaseChannel interface
3. Add configuration schema
4. Write integration tests
5. Document setup process

### Improving Performance

1. Profile code to find bottlenecks
2. Optimize hot paths
3. Add benchmarks
4. Document improvements
5. Ensure tests still pass

## Questions?

Feel free to:
- Open an issue for clarification
- Start a discussion
- Contact maintainers

Thank you for contributing to Nanobot.rb! 🤖 ✨
