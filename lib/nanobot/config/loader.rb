# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'schema'

module Nanobot
  module Config
    # Loader handles loading and saving configuration from/to JSON files
    class Loader
      DEFAULT_CONFIG_PATH = File.expand_path('~/.nanobot/config.json').freeze

      class << self
        # Load configuration from file
        # @param path [String, nil] path to config file (default: ~/.nanobot/config.json)
        # @return [Config]
        def load(path = nil)
          config_path = Pathname.new(path || DEFAULT_CONFIG_PATH)

          unless config_path.exist?
            # Return default config if file doesn't exist
            return Config.new
          end

          begin
            data = JSON.parse(config_path.read, symbolize_names: true)
            Config.new(**data)
          rescue StandardError => e
            raise "Error loading config from #{config_path}: #{e.message}"
          end
        end

        # Save configuration to file
        # @param config [Config] configuration to save
        # @param path [String, nil] path to save to (default: ~/.nanobot/config.json)
        def save(config, path = nil)
          config_path = Pathname.new(path || DEFAULT_CONFIG_PATH)

          # Ensure directory exists
          config_path.dirname.mkpath unless config_path.dirname.exist?

          # Convert to hash and save as JSON
          data = config_to_hash(config)

          config_path.write(JSON.pretty_generate(data))
          FileUtils.chmod(0o600, config_path)
        end

        # Get config path
        # @param path [String, nil] custom path or nil for default
        # @return [Pathname]
        def get_config_path(path = nil)
          Pathname.new(path || DEFAULT_CONFIG_PATH)
        end

        # Check if config exists
        # @param path [String, nil] custom path or nil for default
        # @return [Boolean]
        def exists?(path = nil)
          get_config_path(path).exist?
        end

        # Create default config file with helpful placeholders
        # @param path [String, nil] custom path or nil for default
        # @return [Config]
        def create_default(path = nil)
          config = Config.new(
            providers: {
              anthropic: {
                api_key: 'sk-ant-api03-...'
              },
              openai: {
                api_key: 'sk-...'
              },
              openrouter: {
                api_key: 'sk-or-v1-...',
                api_base: 'https://openrouter.ai/api/v1'
              }
            },
            tools: {
              web: {
                search: {
                  api_key: 'BSA...'
                }
              }
            }
          )
          save(config, path)
          config
        end

        private

        # Convert config to hash for JSON serialization
        # @param config [Config] configuration object
        # @return [Hash] JSON-serializable hash
        def config_to_hash(config)
          hash = {
            providers: providers_to_hash(config.providers),
            provider: config.provider,
            agents: agents_to_hash(config.agents),
            tools: tools_to_hash(config.tools)
          }
          channels = channels_to_hash(config.channels)
          hash[:channels] = channels unless channels.empty?
          hash
        end

        # Serialize providers, omitting unconfigured ones
        # @param providers [ProvidersConfig]
        # @return [Hash]
        def providers_to_hash(providers)
          hash = {}
          providers.each do |key, provider|
            hash[key] = {
              api_key: provider.api_key,
              api_base: provider.api_base,
              extra_headers: provider.extra_headers
            }.compact
          end
          hash
        end

        def agents_to_hash(agents)
          {
            defaults: {
              model: agents.defaults.model,
              workspace: agents.defaults.workspace,
              max_tokens: agents.defaults.max_tokens,
              temperature: agents.defaults.temperature,
              max_tool_iterations: agents.defaults.max_tool_iterations
            }
          }
        end

        def tools_to_hash(tools)
          {
            web: {
              search: {
                api_key: tools.web.search.api_key
              }.compact
            },
            exec: {
              timeout: tools.exec.timeout
            },
            restrict_to_workspace: tools.restrict_to_workspace
          }
        end

        # Serialize channels, omitting disabled ones
        # @param channels [ChannelsConfig, nil]
        # @return [Hash]
        def channels_to_hash(channels)
          return {} unless channels

          hash = {}
          hash[:telegram] = telegram_to_hash(channels.telegram)
          hash[:discord] = discord_to_hash(channels.discord)
          hash[:gateway] = gateway_to_hash(channels.gateway)
          hash[:slack] = slack_to_hash(channels.slack)
          hash[:email] = email_to_hash(channels.email)
          hash.compact
        end

        def telegram_to_hash(telegram)
          return unless telegram&.enabled

          { enabled: telegram.enabled, token: telegram.token,
            allow_from: telegram.allow_from, proxy: telegram.proxy }.compact
        end

        def discord_to_hash(discord)
          return unless discord&.enabled

          { enabled: discord.enabled, token: discord.token,
            allow_from: discord.allow_from }.compact
        end

        def gateway_to_hash(gateway)
          return unless gateway&.enabled

          { enabled: gateway.enabled, host: gateway.host,
            port: gateway.port, auth_token: gateway.auth_token }.compact
        end

        def slack_to_hash(slack)
          return unless slack&.enabled

          { enabled: slack.enabled, bot_token: slack.bot_token,
            app_token: slack.app_token, group_policy: slack.group_policy,
            group_allow_from: slack.group_allow_from,
            dm: { enabled: slack.dm.enabled, policy: slack.dm.policy,
                  allow_from: slack.dm.allow_from } }.compact
        end

        def email_to_hash(email)
          return unless email&.enabled

          email.to_h.compact
        end
      end
    end
  end
end
