# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Config do
  describe 'ProviderConfig' do
    it 'initializes with defaults' do
      config = Nanobot::Config::ProviderConfig.new
      expect(config.api_key).to be_nil
      expect(config.api_base).to be_nil
      expect(config.extra_headers).to be_nil
    end

    it 'accepts parameters' do
      config = Nanobot::Config::ProviderConfig.new(
        api_key: 'test-key',
        api_base: 'https://api.test',
        extra_headers: { 'X-Custom' => 'value' }
      )

      expect(config.api_key).to eq('test-key')
      expect(config.api_base).to eq('https://api.test')
      expect(config.extra_headers).to eq('X-Custom' => 'value')
    end
  end

  describe 'ProvidersConfig' do
    it 'initializes empty by default' do
      config = Nanobot::Config::ProvidersConfig.new
      expect(config).to be_empty
    end

    it 'accepts provider configurations' do
      config = Nanobot::Config::ProvidersConfig.new(
        openai: { api_key: 'openai-key' },
        anthropic: { api_key: 'anthropic-key' }
      )

      expect(config.openai.api_key).to eq('openai-key')
      expect(config.anthropic.api_key).to eq('anthropic-key')
    end

    it 'accepts any provider name' do
      config = Nanobot::Config::ProvidersConfig.new(
        gemini: { api_key: 'gemini-key' },
        ollama: { api_base: 'http://localhost:11434' }
      )

      expect(config.gemini.api_key).to eq('gemini-key')
      expect(config.ollama.api_base).to eq('http://localhost:11434')
    end

    it 'returns nil for unconfigured providers' do
      config = Nanobot::Config::ProvidersConfig.new(openai: { api_key: 'key' })
      expect(config.anthropic).to be_nil
    end

    it 'iterates over configured providers' do
      config = Nanobot::Config::ProvidersConfig.new(
        openai: { api_key: 'a' },
        gemini: { api_key: 'b' }
      )
      collected = {}
      config.each { |k, v| collected[k] = v.api_key }
      expect(collected).to eq(openai: 'a', gemini: 'b')
    end
  end

  describe 'AgentDefaults' do
    it 'initializes with defaults' do
      config = Nanobot::Config::AgentDefaults.new
      expect(config.model).to eq('claude-haiku-4-5')
      expect(config.workspace).to eq('~/.nanobot/workspace')
      expect(config.max_tokens).to eq(4096)
      expect(config.temperature).to eq(0.7)
      expect(config.max_tool_iterations).to eq(20)
    end

    it 'accepts custom values' do
      config = Nanobot::Config::AgentDefaults.new(
        model: 'gpt-4o',
        workspace: '/custom/workspace',
        max_tokens: 8192,
        temperature: 0.5,
        max_tool_iterations: 30
      )

      expect(config.model).to eq('gpt-4o')
      expect(config.workspace).to eq('/custom/workspace')
      expect(config.max_tokens).to eq(8192)
      expect(config.temperature).to eq(0.5)
      expect(config.max_tool_iterations).to eq(30)
    end
  end

  describe 'AgentsConfig' do
    it 'initializes with default AgentDefaults' do
      config = Nanobot::Config::AgentsConfig.new
      expect(config.defaults).to be_a(Nanobot::Config::AgentDefaults)
      expect(config.defaults.model).to eq('claude-haiku-4-5')
    end

    it 'accepts custom defaults' do
      config = Nanobot::Config::AgentsConfig.new(
        defaults: { model: 'custom-model' }
      )
      expect(config.defaults.model).to eq('custom-model')
    end
  end

  describe 'WebSearchConfig' do
    it 'initializes with defaults' do
      config = Nanobot::Config::WebSearchConfig.new
      expect(config.api_key).to be_nil
    end

    it 'accepts api_key' do
      config = Nanobot::Config::WebSearchConfig.new(api_key: 'brave-key')
      expect(config.api_key).to eq('brave-key')
    end
  end

  describe 'ExecToolConfig' do
    it 'initializes with defaults' do
      config = Nanobot::Config::ExecToolConfig.new
      expect(config.timeout).to eq(60)
    end

    it 'accepts custom timeout' do
      config = Nanobot::Config::ExecToolConfig.new(timeout: 120)
      expect(config.timeout).to eq(120)
    end
  end

  describe 'ToolsConfig' do
    it 'initializes with defaults' do
      config = Nanobot::Config::ToolsConfig.new
      expect(config.web.search).to be_a(Nanobot::Config::WebSearchConfig)
      expect(config.exec).to be_a(Nanobot::Config::ExecToolConfig)
      expect(config.restrict_to_workspace).to be false
    end

    it 'accepts custom values' do
      config = Nanobot::Config::ToolsConfig.new(
        web: { search: { api_key: 'brave-key' } },
        exec: { timeout: 120 },
        restrict_to_workspace: true
      )

      expect(config.web.search.api_key).to eq('brave-key')
      expect(config.exec.timeout).to eq(120)
      expect(config.restrict_to_workspace).to be true
    end
  end

  describe 'SchedulerConfig' do
    it 'initializes with defaults' do
      config = Nanobot::Config::SchedulerConfig.new
      expect(config.enabled).to be true
      expect(config.tick_interval).to eq(15)
    end

    it 'accepts custom values' do
      config = Nanobot::Config::SchedulerConfig.new(enabled: false, tick_interval: 30)
      expect(config.enabled).to be false
      expect(config.tick_interval).to eq(30)
    end
  end

  describe 'Config' do
    it 'initializes with defaults' do
      config = Nanobot::Config::Config.new
      expect(config.providers).to be_a(Nanobot::Config::ProvidersConfig)
      expect(config.provider).to eq('anthropic')
      expect(config.agents).to be_a(Nanobot::Config::AgentsConfig)
      expect(config.tools).to be_a(Nanobot::Config::ToolsConfig)
      expect(config.scheduler).to be_a(Nanobot::Config::SchedulerConfig)
    end

    it 'accepts nested configurations' do
      config = Nanobot::Config::Config.new(
        providers: {
          openai: { api_key: 'test-key' }
        },
        provider: 'openai',
        agents: {
          defaults: { model: 'custom-model' }
        },
        tools: {
          exec: { timeout: 90 }
        }
      )

      expect(config.providers.openai.api_key).to eq('test-key')
      expect(config.provider).to eq('openai')
      expect(config.agents.defaults.model).to eq('custom-model')
      expect(config.tools.exec.timeout).to eq(90)
    end

    describe '#api_key' do
      it 'returns API key for the selected provider' do
        config = Nanobot::Config::Config.new(
          providers: {
            anthropic: { api_key: 'anthropic-key' }
          },
          provider: 'anthropic'
        )

        expect(config.api_key).to eq('anthropic-key')
      end

      it 'returns nil when selected provider has no key' do
        config = Nanobot::Config::Config.new(
          providers: {
            openai: { api_key: 'openai-key' }
          },
          provider: 'anthropic'
        )

        expect(config.api_key).to be_nil
      end

      it 'returns nil when no providers configured' do
        config = Nanobot::Config::Config.new
        expect(config.api_key).to be_nil
      end

      it 'uses provider field to select key' do
        config = Nanobot::Config::Config.new(
          providers: {
            groq: { api_key: 'groq-key' },
            anthropic: { api_key: 'anthropic-key' }
          },
          provider: 'groq'
        )

        expect(config.api_key).to eq('groq-key')
      end
    end

    describe '#api_base' do
      it 'returns API base for the selected provider' do
        config = Nanobot::Config::Config.new(
          providers: {
            openrouter: { api_base: 'https://openrouter.ai/api/v1' }
          },
          provider: 'openrouter'
        )

        expect(config.api_base).to eq('https://openrouter.ai/api/v1')
      end

      it 'returns nil when selected provider has no base' do
        config = Nanobot::Config::Config.new
        expect(config.api_base).to be_nil
      end
    end
  end
end
