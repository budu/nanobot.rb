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

    # Telegram channel configuration
    TelegramConfig = Struct.new(:enabled, :token, :allow_from, :proxy, keyword_init: true) do
      def initialize(enabled: false, token: nil, allow_from: [], proxy: nil)
        super
      end
    end

    # Discord channel configuration
    DiscordConfig = Struct.new(:enabled, :token, :allow_from, keyword_init: true) do
      def initialize(enabled: false, token: nil, allow_from: [])
        super
      end
    end

    # HTTP Gateway channel configuration
    GatewayConfig = Struct.new(:enabled, :host, :port, :auth_token, keyword_init: true) do
      def initialize(enabled: false, host: '127.0.0.1', port: 18_790, auth_token: nil)
        super
      end
    end

    # Slack DM policy configuration
    SlackDMConfig = Struct.new(:enabled, :policy, :allow_from, keyword_init: true) do
      def initialize(enabled: true, policy: 'open', allow_from: [])
        super
      end
    end

    # Slack channel configuration
    SlackConfig = Struct.new(
      :enabled, :bot_token, :app_token, :group_policy,
      :group_allow_from, :dm, keyword_init: true
    ) do
      def initialize(
        enabled: false, bot_token: nil, app_token: nil,
        group_policy: 'mention', group_allow_from: [], dm: {}
      )
        dm_config = dm.is_a?(Hash) ? dm : {}
        super(
          enabled: enabled, bot_token: bot_token, app_token: app_token,
          group_policy: group_policy, group_allow_from: group_allow_from,
          dm: SlackDMConfig.new(**dm_config)
        )
      end
    end

    # Email channel configuration
    EmailConfig = Struct.new(
      :enabled, :consent_granted,
      :imap_host, :imap_port, :imap_username, :imap_password,
      :imap_mailbox, :imap_use_ssl,
      :smtp_host, :smtp_port, :smtp_username, :smtp_password,
      :smtp_use_tls, :smtp_use_ssl, :from_address,
      :auto_reply_enabled, :poll_interval_seconds, :mark_seen,
      :max_body_chars, :subject_prefix, :allow_from,
      keyword_init: true
    ) do
      def initialize(
        enabled: false, consent_granted: false,
        imap_host: nil, imap_port: 993, imap_username: nil, imap_password: nil,
        imap_mailbox: 'INBOX', imap_use_ssl: true,
        smtp_host: nil, smtp_port: 587, smtp_username: nil, smtp_password: nil,
        smtp_use_tls: true, smtp_use_ssl: false, from_address: nil,
        auto_reply_enabled: true, poll_interval_seconds: 30, mark_seen: true,
        max_body_chars: 12_000, subject_prefix: 'Re: ', allow_from: []
      )
        super
      end
    end
    # All channels configuration
    ChannelsConfig = Struct.new(:telegram, :discord, :gateway, :slack, :email, keyword_init: true) do
      def initialize(telegram: {}, discord: {}, gateway: {}, slack: {}, email: {})
        super(
          telegram: TelegramConfig.new(**(telegram.is_a?(Hash) ? telegram : {})),
          discord: DiscordConfig.new(**(discord.is_a?(Hash) ? discord : {})),
          gateway: GatewayConfig.new(**(gateway.is_a?(Hash) ? gateway : {})),
          slack: SlackConfig.new(**(slack.is_a?(Hash) ? slack : {})),
          email: EmailConfig.new(**(email.is_a?(Hash) ? email : {}))
        )
      end
    end

    # Main configuration class
    Config = Struct.new(:providers, :provider, :agents, :tools, :channels, keyword_init: true) do
      def initialize(providers: {}, provider: 'anthropic', agents: {}, tools: {}, channels: {}, **_rest)
        channels_config = channels.is_a?(Hash) ? channels : {}
        super(
          providers: ProvidersConfig.new(**providers),
          provider: provider.to_s,
          agents: AgentsConfig.new(**agents),
          tools: ToolsConfig.new(**tools),
          channels: ChannelsConfig.new(**channels_config)
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
