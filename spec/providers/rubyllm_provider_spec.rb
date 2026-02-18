# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Providers::RubyLLMProvider do
  let(:logger) { test_logger }
  let(:provider) { described_class.new(api_key: 'test-key', logger: logger) }

  describe '#initialize' do
    it 'initializes with api_key' do
      expect(provider).to be_a(described_class)
    end

    it 'sets default model' do
      expect(provider.default_model).to eq('claude-haiku-4-5')
    end

    it 'allows custom default model' do
      custom_provider = described_class.new(
        api_key: 'test-key',
        default_model: 'gpt-4o',
        logger: logger
      )
      expect(custom_provider.default_model).to eq('gpt-4o')
    end

    it 'accepts api_base parameter' do
      custom_provider = described_class.new(
        api_key: 'test-key',
        api_base: 'https://custom.api',
        logger: logger
      )
      expect(custom_provider).to be_a(described_class)
    end

    it 'uses provided logger' do
      expect(provider.logger).to eq(logger)
    end
  end

  describe '#chat' do
    let(:messages) { [{ role: 'user', content: 'Hello' }] }
    let(:mock_response) do
      double('response',
             content: 'Hi there!',
             tool_call?: false,
             tool_calls: {})
    end
    let(:mock_provider) { double('provider') }
    let(:mock_model) { double('model') }

    before do
      # Mock RubyLLM Models.resolve and provider.complete
      allow(RubyLLM::Models).to receive(:resolve).and_return([mock_model, mock_provider])
      allow(mock_provider).to receive(:complete).and_return(mock_response)
    end

    it 'makes API call with messages' do
      result = provider.chat(messages: messages)
      expect(result).to be_a(Nanobot::Providers::LLMResponse)
      expect(result.content).to eq('Hi there!')
    end

    it 'uses provided model' do
      provider.chat(messages: messages, model: 'gpt-4o')
      expect(RubyLLM::Models).to have_received(:resolve).with('gpt-4o', config: RubyLLM.config)
    end

    it 'uses default model when not specified' do
      provider.chat(messages: messages)
      expect(RubyLLM::Models).to have_received(:resolve).with('claude-haiku-4-5', config: RubyLLM.config)
    end

    it 'accepts tools parameter' do
      tools = [{ type: 'function', function: { name: 'test' } }]
      result = provider.chat(messages: messages, tools: tools)
      expect(result).to be_a(Nanobot::Providers::LLMResponse)
    end

    it 'accepts max_tokens parameter' do
      result = provider.chat(messages: messages, max_tokens: 2048)
      expect(result).to be_a(Nanobot::Providers::LLMResponse)
    end

    it 'accepts temperature parameter' do
      result = provider.chat(messages: messages, temperature: 0.5)
      expect(result).to be_a(Nanobot::Providers::LLMResponse)
    end

    it 'handles API errors gracefully' do
      allow(RubyLLM::Models).to receive(:resolve).and_raise(StandardError.new('API Error'))

      result = provider.chat(messages: messages)
      expect(result.content).to include('Error calling LLM')
      expect(result.finish_reason).to eq('error')
    end

    it 'logs API calls' do
      allow(logger).to receive(:debug)
      provider.chat(messages: messages)
      expect(logger).to have_received(:debug).at_least(:once)
    end
  end

  describe 'private methods' do
    describe '#configure_client' do
      it 'configures Anthropic API key for anthropic provider' do
        expect do
          described_class.new(api_key: 'sk-ant-test123', provider: 'anthropic', logger: logger)
        end.not_to raise_error
      end

      it 'configures OpenAI API key for openai provider' do
        expect do
          described_class.new(api_key: 'sk-test123', provider: 'openai', logger: logger)
        end.not_to raise_error
      end

      it 'configures OpenRouter API key for openrouter provider' do
        expect do
          described_class.new(api_key: 'sk-or-v1-test', provider: 'openrouter', logger: logger)
        end.not_to raise_error
      end

      it 'silently skips config for unknown provider' do
        allow(logger).to receive(:debug)

        expect do
          described_class.new(api_key: 'sk-test', provider: 'custom_llm', logger: logger)
        end.not_to raise_error
      end
    end

    describe '#log_message' do
      it 'logs system prompt content' do
        allow(logger).to receive(:debug)

        msg = { role: 'system', content: 'You are a helpful assistant' }
        provider.send(:log_message, msg, 0)

        expect(logger).to have_received(:debug).with(match(/system prompt.*You are a helpful assistant/))
      end

      it 'logs tool calls in messages' do
        allow(logger).to receive(:debug)

        msg = {
          role: 'assistant',
          content: '',
          tool_calls: [
            { function: { name: 'read_file', arguments: '{"path":"/tmp"}' } }
          ]
        }
        provider.send(:log_message, msg, 0)

        expect(logger).to have_received(:debug).with(match(/tool_call: read_file/))
      end
    end

    describe '#log_response' do
      it 'logs tool calls from response' do
        allow(logger).to receive(:debug)

        tool_call = Struct.new(:id, :name, :arguments).new('call_1', 'exec', { command: 'ls' })
        response = double('response',
                          content: '',
                          tool_call?: true,
                          tool_calls: { 'call_1' => tool_call })

        provider.send(:log_response, response)

        expect(logger).to have_received(:debug).with(match(/tool_call id=call_1 name=exec/))
      end
    end

    describe '#convert_tool_calls_to_rubyllm' do
      it 'converts tool calls with string arguments' do
        tool_calls = [
          {
            'id' => 'call_1',
            'function' => { 'name' => 'read_file', 'arguments' => '{"path": "/tmp/test.rb"}' }
          }
        ]

        result = provider.send(:convert_tool_calls_to_rubyllm, tool_calls)
        expect(result).to be_a(Hash)
        expect(result['call_1'].name).to eq('read_file')
        expect(result['call_1'].arguments).to eq('path' => '/tmp/test.rb')
      end

      it 'converts tool calls with hash arguments' do
        tool_calls = [
          {
            id: 'call_2',
            function: { name: 'exec', arguments: { command: 'ls' } }
          }
        ]

        result = provider.send(:convert_tool_calls_to_rubyllm, tool_calls)
        expect(result['call_2'].name).to eq('exec')
        expect(result['call_2'].arguments).to eq(command: 'ls')
      end

      it 'returns nil for empty tool calls' do
        expect(provider.send(:convert_tool_calls_to_rubyllm, nil)).to be_nil
        expect(provider.send(:convert_tool_calls_to_rubyllm, [])).to be_nil
      end

      it 'returns nil on JSON parse error' do
        tool_calls = [
          { 'id' => 'call_3', 'function' => { 'name' => 'test', 'arguments' => '{invalid json' } }
        ]

        result = provider.send(:convert_tool_calls_to_rubyllm, tool_calls)
        expect(result).to be_nil
      end
    end

    describe '#convert_tool_calls' do
      it 'returns empty array when no tool calls' do
        response = double('response', tool_call?: false, tool_calls: {})
        result = provider.send(:convert_tool_calls, response)
        expect(result).to eq([])
      end

      it 'converts tool calls to ToolCallRequest format' do
        tool_call_obj = Struct.new(:id, :name, :arguments).new(
          'call_1',
          'test_tool',
          { 'arg' => 'value' }
        )
        response = double('response',
                          tool_call?: true,
                          tool_calls: { 'call_1' => tool_call_obj })

        result = provider.send(:convert_tool_calls, response)
        expect(result.length).to eq(1)
        expect(result.first).to be_a(Nanobot::Providers::ToolCallRequest)
        expect(result.first.name).to eq('test_tool')
        expect(result.first.arguments).to eq('arg' => 'value')
      end
    end
  end
end

RSpec.describe Nanobot::Providers::LLMResponse do
  describe '#initialize' do
    it 'initializes with defaults' do
      response = described_class.new
      expect(response.content).to eq('')
      expect(response.tool_calls).to eq([])
      expect(response.finish_reason).to be_nil
    end

    it 'accepts parameters' do
      tool_calls = [Nanobot::Providers::ToolCallRequest.new(id: '1', name: 'test', arguments: {})]
      response = described_class.new(
        content: 'Test',
        tool_calls: tool_calls,
        finish_reason: 'stop'
      )

      expect(response.content).to eq('Test')
      expect(response.tool_calls).to eq(tool_calls)
      expect(response.finish_reason).to eq('stop')
    end
  end

  describe '#tool_calls?' do
    it 'returns true when tool calls present' do
      tool_calls = [Nanobot::Providers::ToolCallRequest.new(id: '1', name: 'test', arguments: {})]
      response = described_class.new(tool_calls: tool_calls)
      expect(response.tool_calls?).to be true
    end

    it 'returns false when no tool calls' do
      response = described_class.new(tool_calls: [])
      expect(response.tool_calls?).to be false
    end

    it 'returns false when tool_calls is nil' do
      response = described_class.new(tool_calls: nil)
      expect(response.tool_calls?).to be false
    end
  end
end

RSpec.describe Nanobot::Providers::ToolCallRequest do
  describe '#initialize' do
    it 'initializes with keyword arguments' do
      tool_call = described_class.new(
        id: 'call_1',
        name: 'test_tool',
        arguments: { arg: 'value' }
      )

      expect(tool_call.id).to eq('call_1')
      expect(tool_call.name).to eq('test_tool')
      expect(tool_call.arguments).to eq(arg: 'value')
    end
  end
end

RSpec.describe Nanobot::Providers::LLMProvider do
  describe '#chat' do
    it 'raises NotImplementedError' do
      provider = described_class.new
      expect do
        provider.chat(messages: [])
      end.to raise_error(NotImplementedError)
    end
  end

  describe '#default_model' do
    it 'raises NotImplementedError' do
      provider = described_class.new
      expect { provider.default_model }.to raise_error(NotImplementedError)
    end
  end
end
