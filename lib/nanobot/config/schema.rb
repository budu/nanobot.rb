# frozen_string_literal: true

module Nanobot
  module Config
    # Configuration schema classes using plain Ruby hashes and structs

    # Credentials and endpoint for a single LLM provider
    ProviderConfig = Struct.new(:api_key, :api_base, :extra_headers, keyword_init: true) do
      # @param api_key [String, nil] API authentication key
      # @param api_base [String, nil] custom API base URL
      # @param extra_headers [Hash, nil] additional HTTP headers sent with requests
      def initialize(api_key: nil, api_base: nil, extra_headers: nil)
        super
      end
    end

    # Collection of LLM provider configurations, keyed by provider name.
    # Accepts any provider name so new RubyLLM backends work without code changes.
    class ProvidersConfig
      # @param kwargs [Hash] provider name => settings hash pairs
      def initialize(**kwargs)
        @providers = {}
        kwargs.each do |key, value|
          @providers[key.to_sym] = value.is_a?(ProviderConfig) ? value : ProviderConfig.new(**value)
        end
      end

      # Iterate over all configured providers
      # @yieldparam key [Symbol] provider name
      # @yieldparam config [ProviderConfig] provider configuration
      def each(&)
        @providers.each(&)
      end

      # @return [Boolean] true when no providers are configured
      def empty?
        @providers.empty?
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      def method_missing(name, *args)
        return super if name.end_with?('=') || !args.empty?

        @providers[name.to_sym]
      end
    end

    # Default settings applied to all agents unless overridden
    AgentDefaults = Struct.new(
      :model,
      :workspace,
      :max_tokens,
      :temperature,
      :max_tool_iterations,
      :log_level,
      keyword_init: true
    ) do
      # @param model [String] default LLM model identifier
      # @param workspace [String] path to agent workspace directory
      # @param max_tokens [Integer] maximum tokens per LLM response
      # @param temperature [Float] sampling temperature (0.0-1.0)
      # @param max_tool_iterations [Integer] maximum tool call rounds per turn
      # @param log_level [String] logging verbosity (debug, info, warn, error)
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

    # Top-level agents section wrapping agent defaults
    AgentsConfig = Struct.new(:defaults, keyword_init: true) do
      # @param defaults [Hash] agent default settings (see AgentDefaults)
      def initialize(defaults: {})
        super(defaults: AgentDefaults.new(**defaults))
      end
    end

    # Web search tool API settings
    WebSearchConfig = Struct.new(:api_key, keyword_init: true) do
      # @param api_key [String, nil] Brave Search API key
      def initialize(api_key: nil)
        super
      end
    end

    # Shell command execution tool settings
    ExecToolConfig = Struct.new(:timeout, keyword_init: true) do
      # @param timeout [Integer] maximum seconds before killing the process
      def initialize(timeout: 60)
        super
      end
    end

    # Aggregate configuration for all agent tools
    ToolsConfig = Struct.new(:web, :exec, :restrict_to_workspace, keyword_init: true) do
      # @param web [Hash] web tool settings (nested :search key)
      # @param exec [Hash] exec tool settings (see ExecToolConfig)
      # @param restrict_to_workspace [Boolean] limit file tools to workspace directory
      def initialize(web: {}, exec: {}, restrict_to_workspace: true)
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
      # @param enabled [Boolean] whether the Telegram channel is active
      # @param token [String, nil] Telegram Bot API token
      # @param allow_from [Array<String>] allowed usernames or chat IDs
      # @param proxy [String, nil] HTTP proxy URL for Telegram API requests
      def initialize(enabled: false, token: nil, allow_from: [], proxy: nil)
        super
      end
    end

    # Discord channel configuration
    DiscordConfig = Struct.new(:enabled, :token, :allow_from, keyword_init: true) do
      # @param enabled [Boolean] whether the Discord channel is active
      # @param token [String, nil] Discord bot token
      # @param allow_from [Array<String>] allowed user IDs or usernames
      def initialize(enabled: false, token: nil, allow_from: [])
        super
      end
    end

    # HTTP Gateway channel configuration
    GatewayConfig = Struct.new(:enabled, :host, :port, :auth_token, keyword_init: true) do
      # @param enabled [Boolean] whether the HTTP gateway is active
      # @param host [String] bind address for the HTTP server
      # @param port [Integer] listen port for the HTTP server
      # @param auth_token [String, nil] bearer token for authenticating requests
      def initialize(enabled: false, host: '127.0.0.1', port: 18_790, auth_token: nil)
        super
      end
    end

    # Slack direct message policy configuration
    SlackDMConfig = Struct.new(:enabled, :policy, :allow_from, keyword_init: true) do
      # @param enabled [Boolean] whether DM handling is active
      # @param policy [String] access policy: "open" or "restricted"
      # @param allow_from [Array<String>] allowed Slack user IDs when policy is restricted
      def initialize(enabled: true, policy: 'open', allow_from: [])
        super
      end
    end

    # Slack channel configuration
    SlackConfig = Struct.new(
      :enabled, :bot_token, :app_token, :group_policy,
      :group_allow_from, :dm, keyword_init: true
    ) do
      # @param enabled [Boolean] whether the Slack channel is active
      # @param bot_token [String, nil] Slack Bot User OAuth token (xoxb-)
      # @param app_token [String, nil] Slack App-Level token for Socket Mode (xapp-)
      # @param group_policy [String] group message policy: "mention" or "all"
      # @param group_allow_from [Array<String>] allowed channel IDs for group messages
      # @param dm [Hash] direct message settings (see SlackDMConfig)
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

    # Email channel configuration for IMAP polling and SMTP replies
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
      # @param enabled [Boolean] whether the email channel is active
      # @param consent_granted [Boolean] user consent for automated email replies
      # @param imap_host [String, nil] IMAP server hostname
      # @param imap_port [Integer] IMAP server port
      # @param imap_username [String, nil] IMAP login username
      # @param imap_password [String, nil] IMAP login password
      # @param imap_mailbox [String] IMAP mailbox to poll
      # @param imap_use_ssl [Boolean] use SSL for IMAP connection
      # @param smtp_host [String, nil] SMTP server hostname
      # @param smtp_port [Integer] SMTP server port
      # @param smtp_username [String, nil] SMTP login username
      # @param smtp_password [String, nil] SMTP login password
      # @param smtp_use_tls [Boolean] use STARTTLS for SMTP
      # @param smtp_use_ssl [Boolean] use implicit SSL for SMTP
      # @param from_address [String, nil] sender address for outgoing replies
      # @param auto_reply_enabled [Boolean] automatically reply to incoming emails
      # @param poll_interval_seconds [Integer] seconds between IMAP polls
      # @param mark_seen [Boolean] mark processed emails as seen
      # @param max_body_chars [Integer] truncate email body beyond this length
      # @param subject_prefix [String] prefix prepended to reply subjects
      # @param allow_from [Array<String>] allowed sender addresses
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
    # Collection of all messaging channel configurations
    ChannelsConfig = Struct.new(:telegram, :discord, :gateway, :slack, :email, keyword_init: true) do
      # @param telegram [Hash] Telegram channel settings (see TelegramConfig)
      # @param discord [Hash] Discord channel settings (see DiscordConfig)
      # @param gateway [Hash] HTTP gateway settings (see GatewayConfig)
      # @param slack [Hash] Slack channel settings (see SlackConfig)
      # @param email [Hash] email channel settings (see EmailConfig)
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

    # Scheduler service configuration
    SchedulerConfig = Struct.new(:enabled, :tick_interval, keyword_init: true) do
      # @param enabled [Boolean] whether the scheduler service is active
      # @param tick_interval [Integer] seconds between schedule evaluation ticks
      def initialize(enabled: true, tick_interval: 15)
        super
      end
    end

    # Root configuration object holding all Nanobot settings
    Config = Struct.new(:providers, :provider, :agents, :tools, :channels, :scheduler, keyword_init: true) do
      # @param providers [Hash] provider credentials (see ProvidersConfig)
      # @param provider [String] name of the active provider (e.g. "anthropic", "openai")
      # @param agents [Hash] agent settings (see AgentsConfig)
      # @param tools [Hash] tool settings (see ToolsConfig)
      # @param channels [Hash] channel settings (see ChannelsConfig)
      # @param scheduler [Hash] scheduler settings (see SchedulerConfig)
      def initialize(providers: {}, provider: 'anthropic', agents: {}, tools: {}, channels: {}, scheduler: {},
                     **_rest)
        channels_config = channels.is_a?(Hash) ? channels : {}
        scheduler_config = scheduler.is_a?(Hash) ? scheduler : {}
        super(
          providers: ProvidersConfig.new(**providers),
          provider: provider.to_s,
          agents: AgentsConfig.new(**agents),
          tools: ToolsConfig.new(**tools),
          channels: ChannelsConfig.new(**channels_config),
          scheduler: SchedulerConfig.new(**scheduler_config)
        )
      end

      # Get the API key for the selected provider
      # @return [String, nil]
      def api_key
        selected = providers.send(provider.to_sym) if providers.respond_to?(provider.to_sym)
        selected&.api_key
      end

      # Get the API base for the selected provider
      # @return [String, nil]
      def api_base
        selected = providers.send(provider.to_sym) if providers.respond_to?(provider.to_sym)
        selected&.api_base
      end
    end
  end
end
