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

      # rubocop:disable Metrics/ParameterLists
      # Agent loop requires multiple configuration parameters
      def initialize(
        bus:,
        provider:,
        workspace:,
        model: nil,
        max_iterations: 20,
        brave_api_key: nil,
        exec_config: {},
        restrict_to_workspace: false,
        logger: nil
      )
        @bus = bus
        @provider = provider
        @workspace = Pathname.new(workspace).expand_path
        @model = model || provider.default_model
        @max_iterations = max_iterations
        @brave_api_key = brave_api_key
        @exec_config = exec_config
        @restrict_to_workspace = restrict_to_workspace
        @logger = logger || Logger.new(IO::NULL)

        @context = ContextBuilder.new(@workspace, logger: @logger)
        @sessions = Session::Manager.new(@workspace)
        @running = false

        register_default_tools
      end
      # rubocop:enable Metrics/ParameterLists

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
        final_content = agent_loop(messages, session: session)

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

      # Main agent loop: LLM → Tool Calls → Execute → Loop
      # rubocop:disable Metrics
      # Core agent loop logic requires this complexity for orchestration
      def agent_loop(messages, session: nil)
        iteration = 0

        while iteration < @max_iterations
          iteration += 1
          @logger.debug "--- Agent loop iteration #{iteration}/#{@max_iterations} ---"
          @logger.debug "Message history size: #{messages.length} messages"

          response = @provider.chat(
            messages: messages,
            tools: @tool_instances,
            model: @model
          )

          # Handle LLM API errors
          if response.finish_reason == 'error'
            @logger.error "LLM API error: #{response.content}"
            return "[LLM Error] #{response.content}"
          end

          # Check for tool calls
          if response.tool_calls?
            @logger.debug "Got #{response.tool_calls.length} tool call(s), assistant content: #{response.content}"

            # Add assistant message with tool calls
            tool_calls_payload = response.tool_calls.map do |tc|
              {
                id: tc.id,
                type: 'function',
                function: {
                  name: tc.name,
                  arguments: JSON.generate(tc.arguments)
                }
              }
            end

            assistant_msg = {
              role: 'assistant',
              content: response.content || '',
              tool_calls: tool_calls_payload
            }
            messages << assistant_msg
            session&.add_message('assistant', response.content || '', tool_calls: tool_calls_payload)

            # Execute tools and add results
            response.tool_calls.each do |tool_call|
              @logger.debug "Executing tool: #{tool_call.name} id=#{tool_call.id}"
              @logger.debug "  Arguments: #{tool_call.arguments}"

              # Find the matching RubyLLM tool instance
              tool = @tool_instances.find { |t| t.name == tool_call.name }

              if tool
                # Execute using RubyLLM tool's call method
                result = tool.call(tool_call.arguments)
                result_str = result.is_a?(String) ? result : result.to_s
              else
                result_str = "Error: Tool '#{tool_call.name}' not found"
              end

              @logger.debug "  Result (#{result_str.length} chars): #{result_str.slice(0, 1000)}"
              @logger.debug '  (truncated)' if result_str.length > 1000

              tool_msg = {
                role: 'tool',
                tool_call_id: tool_call.id,
                name: tool_call.name,
                content: result_str
              }
              messages << tool_msg
              session&.add_message('tool', result_str)
            end
          else
            # No tool calls - we're done
            @logger.debug "No tool calls, agent loop complete after #{iteration} iteration(s)"
            @logger.debug "Final response: #{response.content}"
            return response.content || "I've completed processing."
          end
        end

        # Max iterations reached
        @logger.warn "Max iterations (#{@max_iterations}) reached"
        "I've completed processing but reached the maximum iteration limit."
      end
      # rubocop:enable Metrics

      # Register default tools (RubyLLM-compatible)
      def register_default_tools
        require_relative 'tools/filesystem'
        require_relative 'tools/shell'
        require_relative 'tools/web'

        allowed_dir = @restrict_to_workspace ? @workspace : nil

        # Create tool instances
        @tool_instances = []

        @tool_instances << Tools::ReadFile.new(allowed_dir: allowed_dir)
        @tool_instances << Tools::WriteFile.new(allowed_dir: allowed_dir)
        @tool_instances << Tools::EditFile.new(allowed_dir: allowed_dir)
        @tool_instances << Tools::ListDir.new(allowed_dir: allowed_dir)

        @tool_instances << Tools::Exec.new(
          working_dir: @workspace.to_s,
          timeout: @exec_config[:timeout] || 60,
          restrict_to_workspace: @restrict_to_workspace
        )

        @tool_instances << Tools::WebSearch.new(api_key: @brave_api_key) if @brave_api_key
        @tool_instances << Tools::WebFetch.new

        # Keep old registry for compatibility (for now we skip MessageTool)
        # @tools.register(Tools::MessageTool.new(bus: @bus))

        @logger.info "Registered #{@tool_instances.length} RubyLLM tools"
      end
    end
  end
end
