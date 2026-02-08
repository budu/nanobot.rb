# frozen_string_literal: true

require 'ruby_llm'
require 'logger'
require_relative 'base'

module Nanobot
  module Providers
    class RubyLLMProvider < LLMProvider
      ToolCallProxy = Struct.new(:id, :name, :arguments)

      attr_reader :logger, :default_model

      def initialize(api_key: nil, api_base: nil, default_model: nil, provider: 'anthropic', logger: nil)
        super()
        @api_key = api_key
        @api_base = api_base
        @provider = provider.to_s
        @default_model = default_model || 'claude-haiku-4-5'
        @logger = logger || Logger.new(IO::NULL)
        @chat = nil

        configure_client
      end

      # Chat with tools using RubyLLM's provider API directly
      # This bypasses RubyLLM's automatic tool execution to give us control
      # @param messages [Array<Hash>] message history with system, user, assistant roles
      # @param tools [Array<RubyLLM::Tool>] array of tool instances
      # @param model [String, nil] model to use
      # @param max_tokens [Integer] max tokens (not used currently)
      # @param temperature [Float] sampling temperature
      # @return [LLMResponse] response with content and tool calls
      # rubocop:disable Metrics/MethodLength
      def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
        model_to_use = model || @default_model

        log_request(model_to_use, temperature, max_tokens, messages, tools)

        begin
          model_obj, provider = RubyLLM::Models.resolve(model_to_use, config: RubyLLM.config)
          ruby_llm_messages = build_rubyllm_messages(messages)
          tools_hash = build_tools_hash(tools)

          response = provider.complete(
            ruby_llm_messages,
            tools: tools_hash,
            temperature: temperature,
            model: model_obj,
            params: {},
            headers: {},
            schema: nil,
            thinking: nil
          )

          log_response(response)

          LLMResponse.new(
            content: response.content,
            tool_calls: convert_tool_calls(response),
            finish_reason: 'stop'
          )
        rescue StandardError => e
          @logger.error "Error calling LLM: #{e.message}"
          @logger.error e.backtrace.join("\n")

          LLMResponse.new(
            content: "Error calling LLM: #{e.message}",
            tool_calls: [],
            finish_reason: 'error'
          )
        end
      end
      # rubocop:enable Metrics/MethodLength

      private

      def log_request(model, temperature, max_tokens, messages, tools)
        @logger.debug '=== LLM REQUEST ==='
        @logger.debug "Model: #{model} | Temperature: #{temperature} | Max tokens: #{max_tokens}"
        @logger.debug "Messages: #{messages.length} total"

        messages.each_with_index do |msg, i|
          log_message(msg, i)
        end

        log_tools(tools)
      end

      def log_message(msg, index)
        role = msg[:role]
        content = msg[:content]
        @logger.debug "  [#{index}] role=#{role} content_length=#{content&.length || 0}"
        if role == 'system'
          @logger.debug "  [#{index}] system prompt (first 500 chars): #{content&.slice(0, 500)}"
        else
          @logger.debug "  [#{index}] content: #{content}"
        end
        msg[:tool_calls]&.each do |tc|
          func = tc[:function] || tc['function']
          name = func[:name] || func['name']
          args = func[:arguments] || func['arguments']
          @logger.debug "  [#{index}] tool_call: #{name}(#{args})"
        end
        @logger.debug "  [#{index}] tool_call_id=#{msg[:tool_call_id]}" if msg[:tool_call_id]
      end

      def log_tools(tools)
        return unless tools && !tools.empty?

        @logger.debug "Tools (#{tools.length}):"
        tools.each do |tool|
          tool_name = tool.respond_to?(:name) ? tool.name : tool[:name] || tool.dig(:function, :name)
          tool_desc = tool.respond_to?(:description) ? tool.description : nil
          @logger.debug "  - #{tool_name}#{": #{tool_desc.slice(0, 120)}" if tool_desc}"
        end
      end

      def log_response(response)
        @logger.debug '=== LLM RESPONSE ==='
        @logger.debug "Content length: #{response.content&.length || 0}"
        @logger.debug "Content: #{response.content}"
        if response.tool_call?
          @logger.debug "Tool calls: #{response.tool_calls.length}"
          response.tool_calls.each_value do |tc|
            @logger.debug "  tool_call id=#{tc.id} name=#{tc.name} args=#{tc.arguments}"
          end
        else
          @logger.debug 'Tool calls: none'
        end
        @logger.debug '=== END LLM RESPONSE ==='
      end

      def build_rubyllm_messages(messages)
        messages.map do |msg|
          RubyLLM::Message.new(
            role: msg[:role].to_sym,
            content: msg[:content] || '',
            tool_calls: convert_tool_calls_to_rubyllm(msg[:tool_calls]),
            tool_call_id: msg[:tool_call_id]
          )
        end
      end

      def build_tools_hash(tools)
        tools_hash = {}
        if tools && !tools.empty?
          tools.each do |tool|
            tools_hash[tool.name.to_sym] = tool
          end
        end
        tools_hash
      end

      def configure_client
        return unless @api_key

        RubyLLM.configure do |config|
          case @provider
          when 'anthropic'
            config.anthropic_api_key = @api_key
          when 'openai', 'deepseek', 'groq'
            config.openai_api_key = @api_key
          when 'openrouter'
            config.openrouter_api_key = @api_key
          else
            @logger.warn "Unknown provider '#{@provider}', defaulting to OpenAI-compatible config"
            config.openai_api_key = @api_key
          end
        end

        @logger.debug "Configured RubyLLM for provider: #{@provider}"
      end

      # Convert RubyLLM tool calls to our format
      def convert_tool_calls(response)
        return [] unless response.tool_call?

        response.tool_calls.map do |_id, tool_call|
          ToolCallRequest.new(
            id: tool_call.id,
            name: tool_call.name,
            arguments: tool_call.arguments
          )
        end
      end

      # Convert our tool call format to RubyLLM format (for history replay)
      def convert_tool_calls_to_rubyllm(tool_calls)
        return nil unless tool_calls && !tool_calls.empty?

        # Convert array of tool calls to hash keyed by ID
        tool_calls.each_with_object({}) do |tc, hash|
          func = tc['function'] || tc[:function]
          args = func['arguments'] || func[:arguments]

          # Parse arguments if they're a JSON string
          require 'json'
          parsed_args = args.is_a?(String) ? JSON.parse(args) : args

          # Create a simple object to represent the tool call
          tool_call_id = tc['id'] || tc[:id]
          tool_call_obj = ToolCallProxy.new(
            tool_call_id,
            func['name'] || func[:name],
            parsed_args
          )

          hash[tool_call_id] = tool_call_obj
        end
      rescue JSON::ParserError
        nil
      end
    end
  end
end
