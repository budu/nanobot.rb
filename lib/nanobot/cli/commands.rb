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
    # Thor-based CLI providing commands for onboarding, running the agent,
    # serving as a multi-channel service, and checking status.
    # rubocop:disable Metrics/ClassLength
    class Commands < Thor
      def self.exit_on_failure?
        true
      end

      desc 'onboard', 'Initialize nanobot configuration and workspace'
      def onboard
        config_path = Config::Loader.get_config_path
        config = load_or_create_config(config_path)

        workspace = Pathname.new(config.agents.defaults.workspace).expand_path
        setup_workspace(workspace)
        create_bootstrap_files(workspace)

        print_onboard_instructions(config_path, workspace)
      end

      desc 'agent', 'Run agent in interactive or single-message mode'
      method_option :message, aliases: '-m', type: :string, desc: 'Single message to process'
      method_option :model, type: :string, desc: 'Model to use (overrides config)'
      method_option :debug, aliases: '-d', type: :boolean, default: false, desc: 'Enable verbose debug logging'
      def agent
        agent_loop = build_agent_loop(model: options[:model], debug: options[:debug])

        if options[:message]
          run_single_message(agent_loop, options[:message])
        else
          run_interactive(agent_loop)
        end
      end

      desc 'serve', 'Start nanobot as a multi-channel service'
      method_option :debug, aliases: '-d', type: :boolean, default: false, desc: 'Enable verbose debug logging'
      def serve
        config, bus, logger = load_runtime(debug: options[:debug])

        # Initialize scheduler
        schedule_store = Scheduler::ScheduleStore.new
        scheduler_service = nil
        if config.scheduler.enabled
          scheduler_service = Scheduler::SchedulerService.new(
            store: schedule_store, bus: bus, logger: logger,
            tick_interval: config.scheduler.tick_interval
          )
        end

        agent_loop = build_agent_loop_from(config, bus, logger, schedule_store: schedule_store)

        require_relative '../channels/manager'
        manager = Channels::Manager.new(config: config, bus: bus, logger: logger)
        register_channels(manager, config, bus, logger)
        manager.start_all

        # Start scheduler after channels so response routing has subscribers
        scheduler_service&.start

        setup_signal_traps(manager, agent_loop, logger, scheduler_service: scheduler_service)

        puts 'Nanobot service started. Press Ctrl+C to stop.'
        agent_loop.run
      end

      desc 'status', 'Show nanobot status and configuration'
      def status
        config_path = Config::Loader.get_config_path

        unless config_path.exist?
          puts "Configuration not found. Run 'nanobot onboard' first."
          return
        end

        config = Config::Loader.load
        print_status(config, config_path)
      end

      desc 'version', 'Show nanobot version'
      def version
        puts "Nanobot version #{Nanobot::VERSION}"
      end

      # Maps channel config keys to their class names for dynamic loading.
      CHANNEL_TYPES = {
        telegram: 'Telegram',
        discord: 'Discord',
        gateway: 'Gateway',
        slack: 'Slack',
        email: 'Email'
      }.freeze

      # Display names for supported LLM providers.
      PROVIDER_NAMES = { 'openrouter' => 'OpenRouter', 'anthropic' => 'Anthropic', 'openai' => 'OpenAI' }.freeze

      # Default workspace files created during onboarding.
      BOOTSTRAP_FILES = {
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
      }.freeze

      private

      # Instantiate and register all enabled channels with the manager.
      # @param manager [Channels::Manager] channel manager
      # @param config [Config] application configuration
      # @param bus [Bus::MessageBus] message bus
      # @param logger [Logger] logger instance
      def register_channels(manager, config, bus, logger)
        CHANNEL_TYPES.each do |key, class_name|
          channel_config = config.channels.send(key)
          next unless channel_config.enabled

          require_relative "../channels/#{key}"
          klass = Channels.const_get(class_name)
          manager.add_channel(klass.new(name: key.to_s, config: channel_config, bus: bus, logger: logger))
        rescue LoadError => e
          logger.error "Failed to load #{key} channel: #{e.message}"
        end
      end

      # Load config, create logger, and initialize the message bus.
      # @param debug [Boolean] enable debug-level logging
      # @return [Array(Config, Bus::MessageBus, Logger)]
      def load_runtime(debug: false)
        config = load_config
        logger = create_logger(config, debug)
        bus = Bus::MessageBus.new(logger: logger)
        [config, bus, logger]
      end

      # Resolve and validate the workspace directory, exiting if not found.
      # @param config [Config] application configuration
      # @return [Pathname] expanded workspace path
      def require_workspace!(config)
        workspace = Pathname.new(config.agents.defaults.workspace).expand_path
        unless workspace.exist?
          puts "Workspace not found. Run 'nanobot onboard' first."
          exit 1
        end
        workspace
      end

      # Build an Agent::Loop from config with optional model and debug overrides.
      # @param model [String, nil] model name override
      # @param debug [Boolean] enable debug-level logging
      # @return [Agent::Loop]
      def build_agent_loop(model: nil, debug: false)
        config, bus, logger = load_runtime(debug: debug)
        provider = create_provider(config, model, logger: logger)
        workspace = require_workspace!(config)

        Agent::Loop.new(
          bus: bus, provider: provider, workspace: workspace, model: model,
          max_iterations: config.agents.defaults.max_tool_iterations,
          brave_api_key: config.tools.web.search.api_key,
          exec_config: { timeout: config.tools.exec.timeout },
          restrict_to_workspace: config.tools.restrict_to_workspace,
          logger: logger
        )
      end

      # Build an Agent::Loop from pre-existing config, bus, and logger.
      # @param config [Config] application configuration
      # @param bus [Bus::MessageBus] message bus
      # @param logger [Logger] logger instance
      # @param schedule_store [Scheduler::ScheduleStore, nil] schedule store for scheduling tools
      # @return [Agent::Loop]
      def build_agent_loop_from(config, bus, logger, schedule_store: nil)
        provider = create_provider(config, nil, logger: logger)
        workspace = require_workspace!(config)

        Agent::Loop.new(
          bus: bus, provider: provider, workspace: workspace,
          max_iterations: config.agents.defaults.max_tool_iterations,
          brave_api_key: config.tools.web.search.api_key,
          exec_config: { timeout: config.tools.exec.timeout },
          restrict_to_workspace: config.tools.restrict_to_workspace,
          schedule_store: schedule_store,
          logger: logger
        )
      end

      # Process a single message through the agent and print the response.
      # @param agent_loop [Agent::Loop] agent loop instance
      # @param message [String] user message
      def run_single_message(agent_loop, message)
        puts 'Processing message...'
        response = agent_loop.process_direct(message)
        puts "\nResponse:"
        puts response
      end

      # Run a REPL-style interactive session reading from stdin.
      # @param agent_loop [Agent::Loop] agent loop instance
      def run_interactive(agent_loop)
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

      # Register INT and TERM signal handlers for graceful shutdown.
      # @param manager [Channels::Manager] channel manager to stop
      # @param agent_loop [Agent::Loop] agent loop to stop
      # @param logger [Logger] logger instance
      # @param scheduler_service [Scheduler::SchedulerService, nil] scheduler to stop
      def setup_signal_traps(manager, agent_loop, logger, scheduler_service: nil)
        %w[INT TERM].each do |signal|
          trap(signal) do
            logger.info "Received #{signal} signal, shutting down..."
            scheduler_service&.stop
            manager.stop_all
            agent_loop.stop
          end
        end
      end

      def load_or_create_config(config_path)
        if config_path.exist?
          puts "Configuration already exists at #{config_path}"
          print 'Overwrite config.json? (y/N): '
          return Config::Loader.load unless $stdin.gets.chomp.downcase == 'y'
        end

        config = Config::Loader.create_default
        puts "Created configuration at #{config_path}"
        config
      end

      def setup_workspace(workspace)
        workspace.mkpath unless workspace.exist?
        puts "Created workspace at #{workspace}"

        memory_dir = workspace / 'memory'
        memory_dir.mkpath unless memory_dir.exist?
        puts "Created memory directory at #{memory_dir}"
      end

      def print_onboard_instructions(config_path, workspace)
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

      def print_status(config, config_path)
        puts "Configuration: #{config_path}"
        puts "Workspace: #{config.agents.defaults.workspace}"
        puts "Model: #{config.agents.defaults.model}"

        puts "\nProviders:"
        PROVIDER_NAMES.each do |key, display_name|
          provider = config.providers.send(key)
          status = provider&.api_key ? 'configured' : 'not configured'
          puts "  #{display_name}: #{status}"
        end
        puts "\nActive provider: #{config.provider}"

        puts "\nChannels:"
        CHANNEL_TYPES.each_key do |key|
          channel = config.channels.send(key)
          puts "  #{key.to_s.capitalize}: #{channel.enabled ? 'enabled' : 'disabled'}"
        end
      end

      def load_config
        unless Config::Loader.exists?
          puts "Configuration not found. Run 'nanobot onboard' first."
          exit 1
        end

        Config::Loader.load
      end

      # Create a Logger to stderr with level from config or debug flag.
      # @param config [Config] application configuration
      # @param debug_flag [Boolean] if true, force DEBUG level
      # @return [Logger]
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

      # Create an LLM provider instance, validating the API key is set and not a placeholder.
      # @param config [Config] application configuration
      # @param model_override [String, nil] optional model name override
      # @param logger [Logger, nil] optional logger
      # @return [Providers::RubyLLMProvider]
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

      def create_bootstrap_files(workspace)
        BOOTSTRAP_FILES.each do |filename, content|
          file_path = workspace / filename
          next if file_path.exist?

          file_path.write(content)
          puts "Created #{file_path}"
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
