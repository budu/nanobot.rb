# frozen_string_literal: true

module Nanobot
  module Config
    # Configuration schema classes using plain Ruby hashes and structs

    # Provider configuration
    ProviderConfig = Struct.new(:api_key, :api_base, :extra_headers, keyword_init: true) do
      def initialize(api_key: nil, api_base: nil, extra_headers: nil)
        super
      end
    end

    # All providers configuration
    ProvidersConfig = Struct.new(
      :openrouter,
      :anthropic,
      :openai,
      :deepseek,
      :groq,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super(
          openrouter: kwargs[:openrouter] ? ProviderConfig.new(**kwargs[:openrouter]) : nil,
          anthropic: kwargs[:anthropic] ? ProviderConfig.new(**kwargs[:anthropic]) : nil,
          openai: kwargs[:openai] ? ProviderConfig.new(**kwargs[:openai]) : nil,
          deepseek: kwargs[:deepseek] ? ProviderConfig.new(**kwargs[:deepseek]) : nil,
          groq: kwargs[:groq] ? ProviderConfig.new(**kwargs[:groq]) : nil
        )
      end
    end

    # Agent defaults configuration
    AgentDefaults = Struct.new(
      :model,
      :workspace,
      :max_tokens,
      :temperature,
      :max_tool_iterations,
      :log_level,
      keyword_init: true
    ) do
      def initialize(
        model: 'claude-haiku-4-5',
        workspace: '~/.nanobot/workspace',
        max_tokens: 4096,
        temperature: 0.7,
        max_tool_iterations: 20,
        log_level: 'info'
      )
        super
      end
    end

    # Agents configuration
    AgentsConfig = Struct.new(:defaults, keyword_init: true) do
      def initialize(defaults: {})
        super(defaults: AgentDefaults.new(**defaults))
      end
    end

    # Web search configuration
    WebSearchConfig = Struct.new(:api_key, keyword_init: true) do
      def initialize(api_key: nil)
        super
      end
    end

    # Exec tool configuration
    ExecToolConfig = Struct.new(:timeout, keyword_init: true) do
      def initialize(timeout: 60)
        super
      end
    end

    # Tools configuration
    ToolsConfig = Struct.new(:web, :exec, :restrict_to_workspace, keyword_init: true) do
      def initialize(web: {}, exec: {}, restrict_to_workspace: false)
        web_config = web.is_a?(Hash) ? web : {}
        exec_config = exec.is_a?(Hash) ? exec : {}

        super(
          web: Struct.new(:search, keyword_init: true).new(
            search: WebSearchConfig.new(**(web_config[:search] || {}))
          ),
          exec: ExecToolConfig.new(**exec_config),
          restrict_to_workspace: restrict_to_workspace
        )
      end
    end

    # Main configuration class
    Config = Struct.new(:providers, :provider, :agents, :tools, keyword_init: true) do
      def initialize(
        providers: {},
        provider: 'anthropic',
        agents: {},
        tools: {},
        **_rest
      )
        super(
          providers: ProvidersConfig.new(**providers),
          provider: provider.to_s,
          agents: AgentsConfig.new(**agents),
          tools: ToolsConfig.new(**tools)
        )
      end

      # Get the API key for the selected provider
      def api_key
        selected = providers.send(provider.to_sym) if providers.respond_to?(provider.to_sym)
        selected&.api_key
      end

      # Get the API base for the selected provider
      def api_base
        selected = providers.send(provider.to_sym) if providers.respond_to?(provider.to_sym)
        selected&.api_base
      end
    end
  end
end
