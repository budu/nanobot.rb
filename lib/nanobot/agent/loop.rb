# frozen_string_literal: true

require 'logger'
require_relative 'context'
require_relative '../session/manager'
require_relative '../bus/events'

module Nanobot
  module Agent
    # AgentLoop is the core processing engine that handles message->response pipeline
    class Loop
      attr_reader :bus, :provider, :workspace, :logger

      # @param bus [Bus::MessageBus] message bus for inbound/outbound messages
      # @param provider [Provider] LLM provider instance
      # @param workspace [String, Pathname] path to the agent workspace directory
      # @param logger [Logger, nil] optional logger instance
      # @param opts [Hash] additional options:
      #   :model [String] LLM model override,
      #   :max_iterations [Integer] max tool-call loop iterations (default 20),
      #   :brave_api_key [String] Brave search API key,
      #   :exec_config [Hash] shell exec configuration,
      #   :restrict_to_workspace [Boolean] restrict file tools to workspace,
      #   :confirm_tool_call [Proc] callback to confirm tool execution,
      #   :schedule_store [Scheduler::ScheduleStore] schedule store for scheduling tools
      def initialize(bus:, provider:, workspace:, logger: nil, **opts)
        @bus = bus
        @provider = provider
        @workspace = Pathname.new(workspace).expand_path
        @model = opts[:model] || provider.default_model
        @max_iterations = opts[:max_iterations] || 20
        @brave_api_key = opts[:brave_api_key]
        @exec_config = opts[:exec_config] || {}
        @restrict_to_workspace = opts.fetch(:restrict_to_workspace, true)
        @confirm_tool_call = opts[:confirm_tool_call]
        @schedule_store = opts[:schedule_store]
        @logger = logger || Logger.new(IO::NULL)

        @context = ContextBuilder.new(@workspace, logger: @logger)
        @sessions = Session::Manager.new(@workspace)
        @running = false

        register_default_tools
      end

      # Start the agent loop (consumes from bus)
      def run
        @running = true
        @logger.info 'Agent loop started'

        loop do
          break unless @running

          begin
            msg = @bus.consume_inbound(timeout: 1)
            next unless msg

            response = process_message(msg)
            @bus.publish_outbound(response) if response
          rescue StandardError => e
            @logger.error "Error processing message: #{e.message}"
            @logger.error e.backtrace.join("\n")
          end
        end
      end

      # Stop the agent loop
      def stop
        @running = false
        @logger.info 'Agent loop stopping'
      end

      # Process a single message directly (for CLI/testing)
      # @param content [String] message content
      # @param channel [String] channel name (default: 'cli')
      # @param chat_id [String] chat ID (default: 'default')
      # @return [String] response content
      def process_direct(content, channel: 'cli', chat_id: 'default')
        msg = Bus::InboundMessage.new(
          channel: channel,
          sender_id: 'user',
          chat_id: chat_id,
          content: content
        )

        response = process_message(msg)
        response&.content
      end

      # Process a message and return a response
      # @param msg [Bus::InboundMessage] inbound message
      # @return [Bus::OutboundMessage, nil] outbound message
      # This method orchestrates message processing and requires complexity
      def process_message(msg)
        @logger.info "Processing message from #{msg.channel}:#{msg.chat_id}"

        # Handle slash commands before LLM processing
        slash_response = handle_slash_command(msg)
        return slash_response if slash_response

        # Get or create session
        session = @sessions.get_or_create(msg.session_key)

        # Build messages for LLM
        messages = @context.build_messages(
          history: session.get_history,
          current_message: msg.content,
          channel: msg.channel,
          chat_id: msg.chat_id
        )

        # Save user message to session
        session.add_message('user', msg.content)

        # Agent loop (also saves intermediate tool call messages to session)
        final_content = agent_loop(messages, session: session, channel: msg.channel)

        # Save final assistant response to session
        session.add_message('assistant', final_content)
        @sessions.save(session)

        # Return response
        Bus::OutboundMessage.new(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: final_content
        )
      rescue StandardError => e
        @logger.error "Error in process_message: #{e.message}"
        @logger.error e.backtrace.join("\n")

        Bus::OutboundMessage.new(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: "Sorry, I encountered an error: #{e.message}"
        )
      end

      private

      # Main agent loop: repeatedly calls LLM and executes tool calls until
      # the LLM returns a final text response or max_iterations is reached
      # @param messages [Array<Hash>] message history in OpenAI format
      # @param session [Session::Session, nil] current session for persistence
      # @param channel [String] channel name for tool scoping
      # @return [String] final response content
      def agent_loop(messages, session: nil, channel: 'cli')
        tools = tools_for_channel(channel)
        iteration = 0

        while iteration < @max_iterations
          iteration += 1
          @logger.debug "--- Agent loop iteration #{iteration}/#{@max_iterations} ---"
          @logger.debug "Message history size: #{messages.length} messages"

          response = @provider.chat(messages: messages, tools: tools, model: @model)

          if response.finish_reason == 'error'
            @logger.error "LLM API error: #{response.content}"
            return "[LLM Error] #{response.content}"
          end

          unless response.tool_calls?
            @logger.debug "No tool calls, agent loop complete after #{iteration} iteration(s)"
            return response.content || "I've completed processing."
          end

          process_tool_calls(response, messages, session, tools)
        end

        @logger.warn "Max iterations (#{@max_iterations}) reached"
        "I've completed processing but reached the maximum iteration limit."
      end

      # Append assistant tool-call message and execute each tool call
      # @param response [Provider::Response] LLM response containing tool calls
      # @param messages [Array<Hash>] message history to append to
      # @param session [Session::Session, nil] session for persistence
      # @param tools [Array<RubyLLM::Tool>] tools available for this request
      def process_tool_calls(response, messages, session, tools)
        @logger.debug "Got #{response.tool_calls.length} tool call(s)"

        payload = serialize_tool_calls(response.tool_calls)
        assistant_msg = { role: 'assistant', content: response.content || '', tool_calls: payload }
        messages << assistant_msg
        session&.add_message('assistant', response.content || '', tool_calls: payload)

        response.tool_calls.each do |tool_call|
          result_str = execute_tool_call(tool_call, tools)
          messages << { role: 'tool', tool_call_id: tool_call.id, name: tool_call.name, content: result_str }
          session&.add_message('tool', result_str)
        end
      end

      # Convert tool call objects to OpenAI-compatible hash format
      # @param tool_calls [Array] tool call objects from provider response
      # @return [Array<Hash>] serialized tool calls
      def serialize_tool_calls(tool_calls)
        tool_calls.map do |tc|
          hash = { id: tc.id, type: 'function', function: { name: tc.name, arguments: JSON.generate(tc.arguments) } }
          hash[:thought_signature] = tc.thought_signature if tc.respond_to?(:thought_signature) && tc.thought_signature
          hash
        end
      end

      # Execute a single tool call, checking user confirmation if configured
      # @param tool_call [Object] tool call with #name, #id, and #arguments
      # @param tools [Array<RubyLLM::Tool>] tools available for this request
      # @return [String] tool execution result
      def execute_tool_call(tool_call, tools)
        @logger.debug "Executing tool: #{tool_call.name} id=#{tool_call.id}"
        @logger.debug "  Arguments: #{tool_call.arguments}"

        result_str = if @confirm_tool_call && !@confirm_tool_call.call(tool_call.name, tool_call.arguments)
                       'Error: Tool execution was denied by user.'
                     else
                       run_tool(tool_call, tools)
                     end

        @logger.debug "  Result (#{result_str.length} chars): #{result_str.slice(0, 1000)}"
        result_str
      end

      # Look up and invoke the tool by name from the scoped tool set.
      # Only tools in the provided set can be invoked — this enforces
      # per-channel tool restrictions even if the LLM hallucinates tool names.
      # @param tool_call [Object] tool call with #name and #arguments
      # @param tools [Array<RubyLLM::Tool>] scoped tool set
      # @return [String] tool result or error message
      def run_tool(tool_call, tools)
        tool = tools.find { |t| t.name == tool_call.name }
        return "Error: Tool '#{tool_call.name}' not found" unless tool

        result = tool.call(tool_call.arguments)
        result.is_a?(String) ? result : result.to_s
      end

      # Handle built-in slash commands (/new, /help) before LLM processing
      # @param msg [Bus::InboundMessage]
      # @return [Bus::OutboundMessage, nil] response if command matched, nil otherwise
      def handle_slash_command(msg)
        case msg.content.strip
        when '/new'
          session = @sessions.get_or_create(msg.session_key)
          session.clear
          @sessions.save(session)
          Bus::OutboundMessage.new(channel: msg.channel, chat_id: msg.chat_id,
                                   content: 'New session started.')
        when '/help'
          Bus::OutboundMessage.new(channel: msg.channel, chat_id: msg.chat_id,
                                   content: help_text)
        end
      end

      # @return [String] formatted help text listing available commands
      def help_text
        "Available commands:\n  " \
          "/new  - Start a new conversation session\n  " \
          "/help - Show this help message\n\n" \
          'Send any other message to chat with the AI assistant.'
      end

      # Channels considered local (full tool access by default)
      LOCAL_CHANNELS = %w[cli].freeze

      # Return the tools available for a given channel.
      # Remote channels (Telegram, Discord, Slack, Email, Gateway) get
      # read-only tools by default to limit blast radius from prompt
      # injection or unauthorized senders.
      # @param channel [String] channel name
      # @return [Array<RubyLLM::Tool>] tools available for this channel
      def tools_for_channel(channel)
        if LOCAL_CHANNELS.include?(channel)
          @tool_instances
        else
          @read_only_tools
        end
      end

      # Register default tools (RubyLLM-compatible)
      def register_default_tools
        require_relative 'tools/filesystem'
        require_relative 'tools/shell'
        require_relative 'tools/web'

        allowed_dir = @restrict_to_workspace ? @workspace : nil

        # Read-only tools (safe for remote channels)
        read_file = Tools::ReadFile.new(allowed_dir: allowed_dir)
        list_dir = Tools::ListDir.new(allowed_dir: allowed_dir)
        web_search = @brave_api_key ? Tools::WebSearch.new(api_key: @brave_api_key) : nil
        web_fetch = Tools::WebFetch.new

        @read_only_tools = [read_file, list_dir, web_fetch]
        @read_only_tools << web_search if web_search

        # Write/exec tools (local channels only by default)
        write_file = Tools::WriteFile.new(allowed_dir: allowed_dir)
        edit_file = Tools::EditFile.new(allowed_dir: allowed_dir)
        exec_tool = Tools::Exec.new(
          working_dir: @workspace.to_s,
          timeout: @exec_config[:timeout] || 60,
          restrict_to_workspace: @restrict_to_workspace
        )

        # Full tool set
        @tool_instances = @read_only_tools + [write_file, edit_file, exec_tool]

        if @schedule_store
          require_relative 'tools/schedule'
          schedule_tools = [
            Tools::ScheduleAdd.new(store: @schedule_store),
            Tools::ScheduleList.new(store: @schedule_store),
            Tools::ScheduleRemove.new(store: @schedule_store)
          ]
          @tool_instances += schedule_tools
          @read_only_tools << Tools::ScheduleList.new(store: @schedule_store)
        end

        @logger.info "Registered #{@tool_instances.length} tools (#{@read_only_tools.length} read-only)"
      end
    end
  end
end
