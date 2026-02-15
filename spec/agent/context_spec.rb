# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Agent::ContextBuilder do
  let(:workspace) { Dir.mktmpdir }
  let(:context_builder) { described_class.new(workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#initialize' do
    it 'initializes with workspace' do
      expect(context_builder.workspace.to_s).to eq(Pathname.new(workspace).expand_path.to_s)
    end

    it 'creates memory store' do
      expect(context_builder.memory_store).to be_a(Nanobot::Agent::MemoryStore)
    end
  end

  describe '#build_system_prompt' do
    it 'includes runtime information' do
      prompt = context_builder.build_system_prompt
      expect(prompt).to include('Runtime Information')
      expect(prompt).to include('OS:')
      expect(prompt).to include('Ruby Version:')
      expect(prompt).to include('Platform:')
      expect(prompt).to include('Workspace:')
      expect(prompt).to include('Current Time:')
    end

    it 'includes bootstrap files when present' do
      (Pathname.new(workspace) / 'AGENTS.md').write('Agent instructions')
      (Pathname.new(workspace) / 'SOUL.md').write('Soul content')

      prompt = context_builder.build_system_prompt
      expect(prompt).to include('AGENTS')
      expect(prompt).to include('Agent instructions')
      expect(prompt).to include('SOUL')
      expect(prompt).to include('Soul content')
    end

    it 'excludes empty bootstrap files' do
      (Pathname.new(workspace) / 'AGENTS.md').write('')

      prompt = context_builder.build_system_prompt
      expect(prompt).not_to include('AGENTS')
    end

    it 'includes memory context when available' do
      memory_store = context_builder.memory_store
      memory_store.write_long_term('Important information')

      prompt = context_builder.build_system_prompt
      expect(prompt).to include('Memory')
      expect(prompt).to include('Important information')
    end

    it 'excludes memory when not available' do
      prompt = context_builder.build_system_prompt
      # Should not have a Memory section if no memory exists
      lines = prompt.lines.map(&:strip)
      expect(lines).not_to include('# Memory')
    end

    it 'handles all bootstrap files' do
      Nanobot::Agent::ContextBuilder::BOOTSTRAP_FILES.each do |filename|
        (Pathname.new(workspace) / filename).write("Content for #{filename}")
      end

      prompt = context_builder.build_system_prompt

      Nanobot::Agent::ContextBuilder::BOOTSTRAP_FILES.each do |filename|
        expect(prompt).to include(filename.sub('.md', ''))
      end
    end

    it 'separates sections with dividers' do
      (Pathname.new(workspace) / 'AGENTS.md').write('Content')
      prompt = context_builder.build_system_prompt
      expect(prompt).to include('---')
    end
  end

  describe '#build_messages' do
    it 'creates messages array with system prompt' do
      messages = context_builder.build_messages(current_message: 'Hello')

      expect(messages).to be_an(Array)
      expect(messages.first[:role]).to eq('system')
      expect(messages.first[:content]).to include('Runtime Information')
    end

    it 'includes current message' do
      messages = context_builder.build_messages(current_message: 'Hello world')

      user_msg = messages.find { |m| m[:role] == 'user' }
      expect(user_msg[:content]).to include('Hello world')
    end

    it 'includes conversation history' do
      history = [
        { role: 'user', content: 'Previous message' },
        { role: 'assistant', content: 'Previous response' }
      ]

      messages = context_builder.build_messages(
        current_message: 'New message',
        history: history
      )

      expect(messages[1][:content]).to eq('Previous message')
      expect(messages[2][:content]).to eq('Previous response')
    end

    it 'adds channel context as a separate system message when provided' do
      messages = context_builder.build_messages(
        current_message: 'Hello',
        channel: 'telegram',
        chat_id: 'chat123'
      )

      # Channel context should be in its own system message, not in user message
      user_msg = messages.last
      expect(user_msg[:role]).to eq('user')
      expect(user_msg[:content]).to eq('Hello')

      context_msg = messages[-2]
      expect(context_msg[:role]).to eq('system')
      expect(context_msg[:content]).to include('telegram')
      expect(context_msg[:content]).to include('chat123')
    end

    it 'does not add channel context when not provided' do
      messages = context_builder.build_messages(current_message: 'Hello')

      system_msgs = messages.select { |m| m[:role] == 'system' }
      expect(system_msgs.length).to eq(1) # Only the main system prompt
    end

    it 'orders messages correctly' do
      history = [
        { role: 'user', content: 'Message 1' },
        { role: 'assistant', content: 'Response 1' }
      ]

      messages = context_builder.build_messages(
        current_message: 'Message 2',
        history: history
      )

      expect(messages[0][:role]).to eq('system')
      expect(messages[1][:role]).to eq('user')
      expect(messages[2][:role]).to eq('assistant')
      expect(messages[3][:role]).to eq('user')
    end

    it 'handles empty history' do
      messages = context_builder.build_messages(
        current_message: 'Hello',
        history: []
      )

      expect(messages.length).to eq(2) # system + user
    end
  end

  describe '#add_tool_result' do
    it 'adds tool result to messages' do
      messages = [
        { role: 'system', content: 'System' },
        { role: 'user', content: 'Use a tool' }
      ]

      updated = context_builder.add_tool_result(
        messages,
        'call_123',
        'test_tool',
        'Tool result'
      )

      tool_msg = updated.last
      expect(tool_msg[:role]).to eq('tool')
      expect(tool_msg[:tool_call_id]).to eq('call_123')
      expect(tool_msg[:name]).to eq('test_tool')
      expect(tool_msg[:content]).to eq('Tool result')
    end

    it 'returns updated messages array' do
      messages = []
      updated = context_builder.add_tool_result(messages, 'id', 'name', 'result')

      expect(updated).to be_an(Array)
      expect(updated.length).to eq(1)
    end

    it 'does not modify original array' do
      messages = [{ role: 'user', content: 'Hello' }]
      original_length = messages.length

      context_builder.add_tool_result(messages, 'id', 'name', 'result')

      expect(messages.length).to eq(original_length + 1)
    end
  end

  describe 'private methods' do
    describe '#build_runtime_info' do
      it 'includes all runtime information' do
        info = context_builder.send(:build_runtime_info)

        expect(info).to include('Runtime Information')
        expect(info).to include('OS:')
        expect(info).to include('Ruby Version:')
        expect(info).to include(RUBY_VERSION)
        expect(info).to include('Platform:')
        expect(info).to include('Workspace:')
        expect(info).to include(workspace)
        expect(info).to include('Current Time:')
      end
    end

    describe '#read_bootstrap_file' do
      it 'reads existing file with header' do
        (Pathname.new(workspace) / 'AGENTS.md').write('Agent content')

        content = context_builder.send(:read_bootstrap_file, 'AGENTS.md')
        expect(content).to include('# AGENTS')
        expect(content).to include('Agent content')
      end

      it 'returns nil for non-existent file' do
        content = context_builder.send(:read_bootstrap_file, 'NONEXISTENT.md')
        expect(content).to be_nil
      end

      it 'returns nil for empty file' do
        (Pathname.new(workspace) / 'EMPTY.md').write('')

        content = context_builder.send(:read_bootstrap_file, 'EMPTY.md')
        expect(content).to be_nil
      end

      it 'returns nil for whitespace-only file' do
        (Pathname.new(workspace) / 'WHITESPACE.md').write("   \n  \n  ")

        content = context_builder.send(:read_bootstrap_file, 'WHITESPACE.md')
        expect(content).to be_nil
      end

      it 'removes .md from header' do
        (Pathname.new(workspace) / 'TEST.md').write('Content')

        content = context_builder.send(:read_bootstrap_file, 'TEST.md')
        expect(content).to start_with('# TEST')
        expect(content).not_to include('# TEST.md')
      end
    end
  end

  describe 'integration' do
    it 'builds complete system prompt with all components' do
      # Setup bootstrap files
      (Pathname.new(workspace) / 'AGENTS.md').write('Agent instructions')
      (Pathname.new(workspace) / 'SOUL.md').write('Agent personality')

      # Setup memory
      context_builder.memory_store.write_long_term('Long-term knowledge')
      context_builder.memory_store.write_today('Today\'s notes')

      prompt = context_builder.build_system_prompt

      expect(prompt).to include('Runtime Information')
      expect(prompt).to include('AGENTS')
      expect(prompt).to include('SOUL')
      expect(prompt).to include('Memory')
      expect(prompt).to include('Long-term knowledge')
    end

    it 'builds complete messages with history and context' do
      (Pathname.new(workspace) / 'AGENTS.md').write('Instructions')

      history = [
        { role: 'user', content: 'First message' },
        { role: 'assistant', content: 'First response' }
      ]

      messages = context_builder.build_messages(
        current_message: 'Second message',
        history: history,
        channel: 'telegram',
        chat_id: 'chat1'
      )

      expect(messages[0][:role]).to eq('system')
      expect(messages[0][:content]).to include('Instructions')
      expect(messages[1][:content]).to eq('First message')
      expect(messages[2][:content]).to eq('First response')
      expect(messages[3][:role]).to eq('system')
      expect(messages[3][:content]).to include('telegram')
      expect(messages[4][:content]).to eq('Second message')
    end
  end
end
