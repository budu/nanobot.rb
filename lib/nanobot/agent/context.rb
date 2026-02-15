# frozen_string_literal: true

require 'rbconfig'
require 'logger'
require_relative 'memory'

module Nanobot
  module Agent
    # ContextBuilder assembles the system prompt and message context for LLM calls
    class ContextBuilder
      BOOTSTRAP_FILES = %w[AGENTS.md SOUL.md USER.md TOOLS.md IDENTITY.md].freeze

      attr_reader :workspace, :memory_store

      def initialize(workspace, logger: nil)
        @workspace = Pathname.new(workspace).expand_path
        @memory_store = MemoryStore.new(@workspace)
        @logger = logger || Logger.new(IO::NULL)
      end

      # Build the complete system prompt
      # @return [String]
      def build_system_prompt
        parts = []

        # Runtime information
        parts << build_runtime_info

        # Bootstrap files
        BOOTSTRAP_FILES.each do |filename|
          content = read_bootstrap_file(filename)
          if content
            parts << content
            @logger.debug "Loaded bootstrap file: #{filename} (#{content.length} chars)"
          else
            @logger.debug "Bootstrap file not found or empty: #{filename}"
          end
        end

        # Memory context
        memory_context = @memory_store.get_memory_context
        if memory_context
          parts << "# Memory\n\n#{memory_context}"
          @logger.debug "Loaded memory context (#{memory_context.length} chars)"
        end

        prompt = parts.join("\n\n---\n\n")
        @logger.debug "System prompt assembled: #{prompt.length} chars total"
        prompt
      end

      # Build messages array for LLM
      # @param history [Array<Hash>] conversation history
      # @param current_message [String] current user message
      # @param channel [String, nil] current channel name
      # @param chat_id [String, nil] current chat ID
      # @return [Array<Hash>] messages in OpenAI format
      def build_messages(current_message:, history: [], channel: nil, chat_id: nil)
        messages = []

        # System prompt
        system_prompt = build_system_prompt
        messages << { role: 'system', content: system_prompt }

        # Add history
        history.each do |msg|
          messages << msg
        end
        @logger.debug "History: #{history.length} messages"

        # Add channel context as a separate system message if provided
        if channel && chat_id
          messages << { role: 'system', content: "Current channel: #{channel}, Chat ID: #{chat_id}" }
        end

        # Add current message
        messages << { role: 'user', content: current_message }
        @logger.debug "Built #{messages.length} messages for LLM"

        messages
      end

      # Add a tool result to messages
      # @param messages [Array<Hash>] existing messages
      # @param tool_call_id [String] ID of the tool call
      # @param tool_name [String] name of the tool
      # @param result [String] tool execution result
      # @return [Array<Hash>] updated messages
      def add_tool_result(messages, tool_call_id, tool_name, result)
        messages << {
          role: 'tool',
          tool_call_id: tool_call_id,
          name: tool_name,
          content: result
        }
        messages
      end

      private

      def build_runtime_info
        <<~INFO
          # Runtime Information

          - OS: #{RbConfig::CONFIG['host_os']}
          - Ruby Version: #{RUBY_VERSION}
          - Platform: #{RUBY_PLATFORM}
          - Workspace: #{@workspace}
          - Current Time: #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')}
        INFO
      end

      def read_bootstrap_file(filename)
        file_path = @workspace / filename
        return nil unless file_path.exist?

        content = file_path.read.strip
        return nil if content.empty?

        # Return with header
        "# #{filename.sub('.md', '')}\n\n#{content}"
      end
    end
  end
end
