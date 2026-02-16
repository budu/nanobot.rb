# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Agent::Loop do
  let(:workspace) { Dir.mktmpdir }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:provider) { instance_double(Nanobot::Providers::LLMProvider) }
  let(:logger) { test_logger }

  let(:agent_loop) do
    described_class.new(
      bus: bus,
      provider: provider,
      workspace: workspace,
      model: 'test-model',
      max_iterations: 5,
      logger: logger
    )
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#initialize' do
    it 'initializes with required parameters' do
      expect(agent_loop.bus).to eq(bus)
      expect(agent_loop.provider).to eq(provider)
      expect(agent_loop.workspace.to_s).to eq(Pathname.new(workspace).expand_path.to_s)
      expect(agent_loop.logger).to eq(logger)
    end

    it 'uses provider default model when model not specified' do
      allow(provider).to receive(:default_model).and_return('default-model')
      described_class.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        logger: logger
      )
      expect(provider).to have_received(:default_model)
    end

    it 'registers default tools' do
      expect(agent_loop.instance_variable_get(:@tool_instances).size).to be > 0
    end

    it 'registers web search tool when brave_api_key provided' do
      allow(provider).to receive(:default_model).and_return('test-model')
      loop_with_brave = described_class.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        brave_api_key: 'test-key',
        logger: logger
      )
      tool_instances = loop_with_brave.instance_variable_get(:@tool_instances)
      expect(tool_instances.any? { |t| t.name.include?('web_search') }).to be true
    end

    it 'accepts exec_config parameter' do
      allow(provider).to receive(:default_model).and_return('test-model')
      loop_with_exec = described_class.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        exec_config: { timeout: 120 },
        logger: logger
      )
      expect(loop_with_exec).to be_a(described_class)
    end

    it 'accepts restrict_to_workspace parameter' do
      allow(provider).to receive(:default_model).and_return('test-model')
      loop_restricted = described_class.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        restrict_to_workspace: true,
        logger: logger
      )
      expect(loop_restricted).to be_a(described_class)
    end
  end

  describe '#process_direct' do
    it 'processes a direct message and returns response content' do
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(
          content: 'Test response',
          tool_calls: []
        )
      )

      result = agent_loop.process_direct('Hello', channel: 'cli', chat_id: 'test')
      expect(result).to eq('Test response')
    end

    it 'uses default channel and chat_id when not specified' do
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(content: 'Response')
      )

      result = agent_loop.process_direct('Hello')
      expect(result).to eq('Response')
    end
  end

  describe '#process_message' do
    let(:inbound_msg) do
      Nanobot::Bus::InboundMessage.new(
        channel: 'test',
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Test message'
      )
    end

    it 'processes a message and returns outbound message' do
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(
          content: 'Response',
          tool_calls: []
        )
      )

      result = agent_loop.process_message(inbound_msg)

      expect(result).to be_a(Nanobot::Bus::OutboundMessage)
      expect(result.channel).to eq('test')
      expect(result.chat_id).to eq('chat1')
      expect(result.content).to eq('Response')
    end

    it 'handles errors gracefully' do
      allow(provider).to receive(:chat).and_raise(StandardError.new('Test error'))

      result = agent_loop.process_message(inbound_msg)

      expect(result).to be_a(Nanobot::Bus::OutboundMessage)
      expect(result.content).to include('error')
    end

    it 'saves message to session' do
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(content: 'Response')
      )

      agent_loop.process_message(inbound_msg)

      sessions = agent_loop.instance_variable_get(:@sessions)
      session = sessions.get_or_create(inbound_msg.session_key)
      expect(session.message_count).to be > 0
    end
  end

  describe '#run and #stop' do
    it 'starts and stops the agent loop' do
      allow(bus).to receive(:consume_inbound).and_return(nil)

      thread = Thread.new { agent_loop.run }
      sleep 0.1

      agent_loop.stop
      thread.join(1)

      expect(thread.alive?).to be false
    end

    it 'processes messages from bus' do
      msg = Nanobot::Bus::InboundMessage.new(
        channel: 'test',
        sender_id: 'user',
        chat_id: 'chat',
        content: 'Hello'
      )

      allow(bus).to receive(:consume_inbound).and_return(msg, nil)
      allow(bus).to receive(:publish_outbound)
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(content: 'Response')
      )

      thread = Thread.new { agent_loop.run }
      sleep 0.2
      agent_loop.stop
      thread.join(1)

      expect(bus).to have_received(:publish_outbound)
    end

    it 'handles message processing errors in run loop' do
      allow(bus).to receive(:consume_inbound).and_return(
        Nanobot::Bus::InboundMessage.new(
          channel: 'test',
          sender_id: 'user',
          chat_id: 'chat',
          content: 'Hello'
        ),
        nil
      )
      allow(provider).to receive(:chat).and_raise(StandardError.new('Error'))
      allow(bus).to receive(:publish_outbound)

      thread = Thread.new { agent_loop.run }
      sleep 0.2
      agent_loop.stop
      thread.join(1)

      expect(bus).to have_received(:publish_outbound)
    end
  end

  describe 'slash commands' do
    it 'handles /new command by clearing session' do
      # First, send a normal message to create session history
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(content: 'Hello!')
      )
      agent_loop.process_direct('Hello', channel: 'test', chat_id: 'slash_test')

      # Now send /new
      result = agent_loop.process_direct('/new', channel: 'test', chat_id: 'slash_test')
      expect(result).to eq('New session started.')

      # Verify session was cleared
      sessions = agent_loop.instance_variable_get(:@sessions)
      session = sessions.get_or_create('test:slash_test')
      expect(session.message_count).to eq(0)

      # Clean up
      sessions.delete('test:slash_test')
    end

    it 'handles /help command' do
      result = agent_loop.process_direct('/help')
      expect(result).to include('Available commands:')
      expect(result).to include('/new')
      expect(result).to include('/help')
    end

    it 'does not call LLM for slash commands' do
      agent_loop.process_direct('/help')
      expect(provider).not_to have_received(:chat) if provider.respond_to?(:chat)
    end

    it 'passes non-slash messages to LLM' do
      allow(provider).to receive(:chat).and_return(
        Nanobot::Providers::LLMResponse.new(content: 'Response')
      )
      result = agent_loop.process_direct('Hello')
      expect(result).to eq('Response')
    end

    it 'handles /new with whitespace' do
      result = agent_loop.process_direct('  /new  ')
      expect(result).to eq('New session started.')
    end
  end

  describe 'agent loop with tool calls' do
    it 'executes tool calls and continues loop' do
      tool_call = Nanobot::Providers::ToolCallRequest.new(
        id: 'call_1',
        name: 'read_file',
        arguments: { path: 'test.txt' }
      )

      response_with_tools = Nanobot::Providers::LLMResponse.new(
        content: 'I will read the file',
        tool_calls: [tool_call]
      )

      final_response = Nanobot::Providers::LLMResponse.new(
        content: 'Here is the content',
        tool_calls: []
      )

      allow(provider).to receive(:chat)
        .and_return(response_with_tools, final_response)

      result = agent_loop.process_direct('Read test.txt')
      expect(result).to eq('Here is the content')
    end

    it 'reaches max iterations and returns appropriate message' do
      tool_call = Nanobot::Providers::ToolCallRequest.new(
        id: 'call_1',
        name: 'read_file',
        arguments: { path: 'test.txt' }
      )

      response_with_tools = Nanobot::Providers::LLMResponse.new(
        content: 'Processing',
        tool_calls: [tool_call]
      )

      allow(provider).to receive(:chat).and_return(response_with_tools)

      result = agent_loop.process_direct('Test')
      expect(result).to include('maximum iteration limit')
    end

    it 'handles multiple tool calls in one response' do
      tool_call1 = Nanobot::Providers::ToolCallRequest.new(
        id: 'call_1',
        name: 'read_file',
        arguments: { path: 'test1.txt' }
      )

      tool_call2 = Nanobot::Providers::ToolCallRequest.new(
        id: 'call_2',
        name: 'read_file',
        arguments: { path: 'test2.txt' }
      )

      response_with_tools = Nanobot::Providers::LLMResponse.new(
        content: 'Reading files',
        tool_calls: [tool_call1, tool_call2]
      )

      final_response = Nanobot::Providers::LLMResponse.new(
        content: 'Done',
        tool_calls: []
      )

      allow(provider).to receive(:chat)
        .and_return(response_with_tools, final_response)

      result = agent_loop.process_direct('Read files')
      expect(result).to eq('Done')
    end

    it 'handles LLM API errors distinctly' do
      error_response = Nanobot::Providers::LLMResponse.new(
        content: 'Error calling LLM: rate limit exceeded',
        tool_calls: [],
        finish_reason: 'error'
      )

      allow(provider).to receive(:chat).and_return(error_response)

      result = agent_loop.process_direct('Hello')
      expect(result).to include('[LLM Error]')
      expect(result).to include('rate limit exceeded')
    end

    it 'saves intermediate tool call messages to session' do
      tool_call = Nanobot::Providers::ToolCallRequest.new(
        id: 'call_1',
        name: 'read_file',
        arguments: { path: 'test.txt' }
      )

      response_with_tools = Nanobot::Providers::LLMResponse.new(
        content: 'I will read the file',
        tool_calls: [tool_call]
      )

      final_response = Nanobot::Providers::LLMResponse.new(
        content: 'Here is the content',
        tool_calls: []
      )

      allow(provider).to receive(:chat)
        .and_return(response_with_tools, final_response)

      # Use a unique chat_id and clean any prior session state
      chat_id = "session_save_test_#{SecureRandom.hex(4)}"
      inbound_msg = Nanobot::Bus::InboundMessage.new(
        channel: 'test',
        sender_id: 'user1',
        chat_id: chat_id,
        content: 'Read test.txt'
      )

      agent_loop.process_message(inbound_msg)

      sessions = agent_loop.instance_variable_get(:@sessions)
      session = sessions.get_or_create(inbound_msg.session_key)
      messages = session.messages

      # Should have: user, assistant (with tool_calls), tool, assistant (final)
      roles = messages.map { |m| m[:role] }
      expect(roles).to eq(%w[user assistant tool assistant])
      expect(messages[1][:tool_calls]).not_to be_nil

      # Clean up
      sessions.delete(inbound_msg.session_key)
    end
  end
end
