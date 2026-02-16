# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'logger'
require_relative '../config/loader'
require_relative '../providers/rubyllm_provider'
require_relative '../bus/message_bus'
require_relative '../agent/loop'

module Nanobot
  module CLI
    # rubocop:disable Metrics/ClassLength
    class Commands < Thor
      def self.exit_on_failure?
        true
      end

      desc 'onboard', 'Initialize nanobot configuration and workspace'
      # rubocop:disable Metrics/AbcSize
      def onboard
        config_path = Config::Loader.get_config_path

        if config_path.exist?
          config = Config::Loader.load
          puts "Configuration already exists at #{config_path}"
          print 'Overwrite config.json? (y/N): '
          answer = $stdin.gets.chomp.downcase
          if answer == 'y'
            config = Config::Loader.create_default
            puts "Created configuration at #{config_path}"
          end
        else
          config = Config::Loader.create_default
          puts "Created configuration at #{config_path}"
        end

        # Create workspace
        workspace = Pathname.new(config.agents.defaults.workspace).expand_path
        workspace.mkpath unless workspace.exist?
        puts "Created workspace at #{workspace}"

        # Create bootstrap files
        create_bootstrap_files(workspace)

        # Create memory directory
        memory_dir = workspace / 'memory'
        memory_dir.mkpath unless memory_dir.exist?
        puts "Created memory directory at #{memory_dir}"

        puts "\nSetup complete!"
        puts "\nNext steps:"
        puts "1. Edit #{config_path} and replace the placeholder API keys with your actual keys:"
        puts '   - Anthropic: Get key from https://console.anthropic.com/'
        puts '   - OpenAI: Get key from https://platform.openai.com/api-keys'
        puts '   - OpenRouter: Get key from https://openrouter.ai/keys'
        puts '   - Brave Search (optional): Get key from https://brave.com/search/api/'
        puts "2. Customize workspace files in #{workspace}"
        puts "3. Run 'nanobot agent -m \"Hello\"' to test"
      end
      # rubocop:enable Metrics/AbcSize

      desc 'agent', 'Run agent in interactive or single-message mode'
      method_option :message, aliases: '-m', type: :string, desc: 'Single message to process'
      method_option :model, type: :string, desc: 'Model to use (overrides config)'
      method_option :debug, aliases: '-d', type: :boolean, default: false, desc: 'Enable verbose debug logging'
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Agent command orchestrates complex initialization and message processing
      def agent
        config = load_config
        workspace = Pathname.new(config.agents.defaults.workspace).expand_path

        # Ensure workspace exists
        unless workspace.exist?
          puts "Workspace not found. Run 'nanobot onboard' first."
          exit 1
        end

        # Set up logger with appropriate level
        logger = create_logger(config, options[:debug])

        # Create provider
        provider = create_provider(config, options[:model], logger: logger)

        # Create bus and agent
        bus = Bus::MessageBus.new(logger: logger)
        agent_loop = Agent::Loop.new(
          bus: bus,
          provider: provider,
          workspace: workspace,
          model: options[:model],
          max_iterations: config.agents.defaults.max_tool_iterations,
          brave_api_key: config.tools.web.search.api_key,
          exec_config: { timeout: config.tools.exec.timeout },
          restrict_to_workspace: config.tools.restrict_to_workspace,
          logger: logger
        )

        if options[:message]
          # Single message mode
          puts 'Processing message...'
          response = agent_loop.process_direct(options[:message])
          puts "\nResponse:"
          puts response
        else
          # Interactive mode
          puts 'Nanobot Agent (interactive mode)'
          puts "Type 'exit' or 'quit' to exit\n\n"

          loop do
            print '> '
            input = $stdin.gets&.chomp
            break if input.nil? || %w[exit quit].include?(input.downcase)
            next if input.strip.empty?

            begin
              response = agent_loop.process_direct(input)
              puts "\n#{response}\n\n"
            rescue StandardError => e
              puts "Error: #{e.message}"
            end
          end

          puts "\nGoodbye!"
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      desc 'serve', 'Start nanobot as a multi-channel service'
      method_option :debug, aliases: '-d', type: :boolean, default: false, desc: 'Enable verbose debug logging'
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Serve command orchestrates channel startup and agent loop
      def serve
        config = load_config
        workspace = Pathname.new(config.agents.defaults.workspace).expand_path

        unless workspace.exist?
          puts "Workspace not found. Run 'nanobot onboard' first."
          exit 1
        end

        logger = create_logger(config, options[:debug])
        provider = create_provider(config, nil, logger: logger)

        bus = Bus::MessageBus.new(logger: logger)
        agent_loop = Agent::Loop.new(
          bus: bus,
          provider: provider,
          workspace: workspace,
          max_iterations: config.agents.defaults.max_tool_iterations,
          brave_api_key: config.tools.web.search.api_key,
          exec_config: { timeout: config.tools.exec.timeout },
          restrict_to_workspace: config.tools.restrict_to_workspace,
          logger: logger
        )

        require_relative '../channels/manager'
        manager = Channels::Manager.new(config: config, bus: bus, logger: logger)
        register_channels(manager, config, bus, logger)

        manager.start_all

        trap('INT') do
          logger.info 'Received INT signal, shutting down...'
          manager.stop_all
          agent_loop.stop
        end

        trap('TERM') do
          logger.info 'Received TERM signal, shutting down...'
          manager.stop_all
          agent_loop.stop
        end

        puts 'Nanobot service started. Press Ctrl+C to stop.'
        agent_loop.run
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      desc 'status', 'Show nanobot status and configuration'
      # rubocop:disable Metrics/AbcSize
      # Status command displays comprehensive system information
      def status
        config_path = Config::Loader.get_config_path

        if config_path.exist?
          config = Config::Loader.load
          puts "Configuration: #{config_path}"
          puts "Workspace: #{config.agents.defaults.workspace}"
          puts "Model: #{config.agents.defaults.model}"
          puts "\nProviders:"
          puts "  OpenRouter: #{config.providers.openrouter&.api_key ? 'configured' : 'not configured'}"
          puts "  Anthropic: #{config.providers.anthropic&.api_key ? 'configured' : 'not configured'}"
          puts "  OpenAI: #{config.providers.openai&.api_key ? 'configured' : 'not configured'}"
          puts "\nActive provider: #{config.provider}"

          puts "\nChannels:"
          channels = config.channels
          puts "  Telegram: #{channels.telegram.enabled ? 'enabled' : 'disabled'}"
          puts "  Discord: #{channels.discord.enabled ? 'enabled' : 'disabled'}"
          puts "  Gateway: #{channels.gateway.enabled ? 'enabled' : 'disabled'}"
          puts "  Slack: #{channels.slack.enabled ? 'enabled' : 'disabled'}"
          puts "  Email: #{channels.email.enabled ? 'enabled' : 'disabled'}"
        else
          puts "Configuration not found. Run 'nanobot onboard' first."
        end
      end
      # rubocop:enable Metrics/AbcSize

      desc 'version', 'Show nanobot version'
      def version
        puts "Nanobot version #{Nanobot::VERSION}"
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Channel registration requires checking each channel type individually
      def register_channels(manager, config, bus, logger)
        channels_config = config.channels

        if channels_config.telegram.enabled
          begin
            require_relative '../channels/telegram'
            manager.add_channel(Channels::Telegram.new(
                                  name: 'telegram', config: channels_config.telegram, bus: bus, logger: logger
                                ))
          rescue LoadError => e
            logger.error "Failed to load telegram channel: #{e.message}"
          end
        end

        if channels_config.discord.enabled
          begin
            require_relative '../channels/discord'
            manager.add_channel(Channels::Discord.new(
                                  name: 'discord', config: channels_config.discord, bus: bus, logger: logger
                                ))
          rescue LoadError => e
            logger.error "Failed to load discord channel: #{e.message}"
          end
        end

        if channels_config.gateway.enabled
          begin
            require_relative '../channels/gateway'
            manager.add_channel(Channels::Gateway.new(
                                  name: 'gateway', config: channels_config.gateway, bus: bus, logger: logger
                                ))
          rescue LoadError => e
            logger.error "Failed to load gateway channel: #{e.message}"
          end
        end

        if channels_config.slack.enabled
          begin
            require_relative '../channels/slack'
            manager.add_channel(Channels::Slack.new(
                                  name: 'slack', config: channels_config.slack, bus: bus, logger: logger
                                ))
          rescue LoadError => e
            logger.error "Failed to load slack channel: #{e.message}"
          end
        end

        return unless channels_config.email.enabled

        require_relative '../channels/email'
        manager.add_channel(Channels::Email.new(
                              name: 'email', config: channels_config.email, bus: bus, logger: logger
                            ))
      rescue LoadError => e
        logger.error "Failed to load email channel: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def load_config
        unless Config::Loader.exists?
          puts "Configuration not found. Run 'nanobot onboard' first."
          exit 1
        end

        Config::Loader.load
      end

      def create_logger(config, debug_flag)
        logger = Logger.new($stderr)
        logger.formatter = proc do |severity, _datetime, _progname, msg|
          "#{severity}: #{msg}\n"
        end

        if debug_flag
          logger.level = Logger::DEBUG
        else
          level_str = config.agents.defaults.log_level || 'info'
          logger.level = case level_str.downcase
                         when 'debug' then Logger::DEBUG
                         when 'warn' then Logger::WARN
                         when 'error' then Logger::ERROR
                         else Logger::INFO
                         end
        end

        logger
      end

      def create_provider(config, model_override = nil, logger: nil)
        api_key = config.api_key
        api_base = config.api_base
        model = model_override || config.agents.defaults.model

        unless api_key
          puts "No API key configured for provider '#{config.provider}'."
          puts 'Please edit your config file and add an API key.'
          exit 1
        end

        # Check for placeholder keys
        if api_key.match?(/^sk-(ant-api03-)?\.{3}$|^sk-or-v1-\.{3}$|^BSA\.{3}$/)
          puts 'Placeholder API key detected. Please replace it with your actual API key.'
          puts 'Edit your config file and add a real API key from:'
          puts '  - Anthropic: https://console.anthropic.com/'
          puts '  - OpenAI: https://platform.openai.com/api-keys'
          puts '  - OpenRouter: https://openrouter.ai/keys'
          exit 1
        end

        Providers::RubyLLMProvider.new(
          api_key: api_key,
          api_base: api_base,
          default_model: model,
          provider: config.provider,
          logger: logger
        )
      end

      # rubocop:disable Metrics/MethodLength
      # Bootstrap files creation requires multiple file definitions
      def create_bootstrap_files(workspace)
        files = {
          'AGENTS.md' => <<~CONTENT,
            # Agent Instructions

            You are Nanobot, a helpful AI assistant.

            ## Your Capabilities
            - Read and write files
            - Execute shell commands
            - Search the web
            - Fetch and parse web pages
            - Manage your own memory

            ## Guidelines
            - Be helpful and concise
            - Ask clarifying questions when needed
            - Use tools proactively to accomplish tasks
            - Save important information to memory
          CONTENT
          'SOUL.md' => <<~CONTENT,
            # Agent Values

            ## Core Principles
            - Helpfulness: Always strive to assist the user
            - Honesty: Be truthful and transparent
            - Safety: Avoid harmful actions
            - Respect: Treat users with respect
          CONTENT
          'USER.md' => <<~CONTENT,
            # User Profile

            ## Preferences
            (Add your preferences here)

            ## Context
            (Add relevant context about yourself here)
          CONTENT
          'TOOLS.md' => <<~CONTENT,
            # Available Tools

            ## File Operations
            - read_file: Read file contents
            - write_file: Write to a file
            - edit_file: Edit a file by replacing text
            - list_dir: List directory contents

            ## System
            - exec: Execute shell commands (with security restrictions)

            ## Web
            - web_search: Search the web using Brave Search (requires API key)
            - web_fetch: Fetch and parse web pages
          CONTENT
          'IDENTITY.md' => <<~CONTENT
            # Agent Identity

            - Name: Nanobot
            - Creature: AI
            - Vibe: warm
            - Emoji: 🤖
            - Avatar: (workspace-relative path, URL, or data URI)
          CONTENT
        }

        files.each do |filename, content|
          file_path = workspace / filename
          next if file_path.exist?

          file_path.write(content)
          puts "Created #{file_path}"
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
    # rubocop:enable Metrics/ClassLength
  end
end
