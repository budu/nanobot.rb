# frozen_string_literal: true

require 'ruby_llm'
require 'logger'
require_relative 'base'

module Nanobot
  module Providers
    # LLM provider implementation backed by the RubyLLM gem.
    # Supports all RubyLLM backends (Anthropic, OpenAI, Gemini, DeepSeek,
    # OpenRouter, Mistral, Perplexity, xAI, Ollama, GPUStack, Bedrock, etc.).
    class RubyLLMProvider < LLMProvider
      # Lightweight struct for replaying tool calls through RubyLLM message history.
      # Includes thought_signature for Gemini provider compatibility.
      ToolCallProxy = Struct.new(:id, :name, :arguments, :thought_signature)

      # Maps nanobot provider names to their RubyLLM api_key config attribute.
      # Providers not listed here (or mapped to nil) have no api_key setting.
      PROVIDER_KEY_MAP = {
        'anthropic' => :anthropic_api_key,
        'openai' => :openai_api_key,
        'gemini' => :gemini_api_key,
        'deepseek' => :deepseek_api_key,
        'openrouter' => :openrouter_api_key,
        'mistral' => :mistral_api_key,
        'perplexity' => :perplexity_api_key,
        'xai' => :xai_api_key,
        'gpustack' => :gpustack_api_key,
        'bedrock' => :bedrock_api_key,
        'groq' => :openai_api_key
      }.freeze

      # Maps nanobot provider names to their RubyLLM api_base config attribute.
      # Only providers that support a custom base URL are listed.
      PROVIDER_BASE_MAP = {
        'openai' => :openai_api_base,
        'gemini' => :gemini_api_base,
        'ollama' => :ollama_api_base,
        'gpustack' => :gpustack_api_base
      }.freeze

      attr_reader :logger, :default_model

      # @param api_key [String, nil] API key for the provider
      # @param api_base [String, nil] custom API base URL
      # @param default_model [String, nil] model identifier (defaults to claude-haiku-4-5)
      # @param provider [String] provider backend name (anthropic, openai, deepseek, groq, openrouter)
      # @param logger [Logger, nil] logger instance (defaults to null logger)
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
      def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
        model_to_use = model || @default_model
        log_request(model_to_use, temperature, max_tokens, messages, tools)

        response = call_provider(model_to_use, messages, tools, temperature)
        log_response(response)

        LLMResponse.new(content: response.content, tool_calls: convert_tool_calls(response), finish_reason: 'stop')
      rescue StandardError => e
        @logger.error "Error calling LLM: #{e.message}"
        @logger.error e.backtrace.join("\n")

        LLMResponse.new(content: "Error calling LLM: #{e.message}", tool_calls: [], finish_reason: 'error')
      end

      private

      # Resolve the model and invoke the RubyLLM provider API directly.
      # @param model_id [String] model identifier
      # @param messages [Array<Hash>] message history
      # @param tools [Array<RubyLLM::Tool>, nil] available tools
      # @param temperature [Float] sampling temperature
      # @return [RubyLLM::Message] provider response
      def call_provider(model_id, messages, tools, temperature)
        model_obj, provider = RubyLLM::Models.resolve(model_id, config: RubyLLM.config)

        provider.complete(
          build_rubyllm_messages(messages),
          tools: build_tools_hash(tools),
          temperature: temperature,
          model: model_obj,
          params: {},
          headers: {},
          schema: nil,
          thinking: nil
        )
      end

      # Log the outgoing LLM request details at debug level.
      def log_request(model, temperature, max_tokens, messages, tools)
        @logger.debug '=== LLM REQUEST ==='
        @logger.debug "Model: #{model} | Temperature: #{temperature} | Max tokens: #{max_tokens}"
        @logger.debug "Messages: #{messages.length} total"

        messages.each_with_index do |msg, i|
          log_message(msg, i)
        end

        log_tools(tools)
      end

      # Log a single message's role, content, and any tool calls.
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

      # Log available tool names and descriptions.
      def log_tools(tools)
        return unless tools && !tools.empty?

        @logger.debug "Tools (#{tools.length}):"
        tools.each do |tool|
          tool_name = tool.respond_to?(:name) ? tool.name : tool[:name] || tool.dig(:function, :name)
          tool_desc = tool.respond_to?(:description) ? tool.description : nil
          @logger.debug "  - #{tool_name}#{": #{tool_desc.slice(0, 120)}" if tool_desc}"
        end
      end

      # Log the LLM response content and tool calls.
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

      # Convert internal message hashes to RubyLLM::Message objects.
      # @param messages [Array<Hash>] message hashes with :role, :content, :tool_calls, :tool_call_id
      # @return [Array<RubyLLM::Message>]
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

      # Convert an array of tool instances to a hash keyed by tool name.
      # @param tools [Array<RubyLLM::Tool>, nil] tool instances
      # @return [Hash{Symbol => RubyLLM::Tool}]
      def build_tools_hash(tools)
        tools_hash = {}
        if tools && !tools.empty?
          tools.each do |tool|
            tools_hash[tool.name.to_sym] = tool
          end
        end
        tools_hash
      end

      # Configure the RubyLLM client with the appropriate API key and base URL for the provider.
      def configure_client
        RubyLLM.configure do |config|
          key_attr = PROVIDER_KEY_MAP[@provider]
          config.send(:"#{key_attr}=", @api_key) if key_attr && @api_key

          base_attr = PROVIDER_BASE_MAP[@provider]
          config.send(:"#{base_attr}=", @api_base) if base_attr && @api_base
        end

        @logger.debug "Configured RubyLLM for provider: #{@provider}"
      end

      # Convert RubyLLM tool calls to our ToolCallRequest format.
      # @param response [RubyLLM::Message] LLM response
      # @return [Array<ToolCallRequest>]
      def convert_tool_calls(response)
        return [] unless response.tool_call?

        response.tool_calls.map do |_id, tool_call|
          ToolCallRequest.new(
            id: tool_call.id,
            name: tool_call.name,
            arguments: tool_call.arguments,
            thought_signature: tool_call.respond_to?(:thought_signature) ? tool_call.thought_signature : nil
          )
        end
      end

      # Convert our tool call format to RubyLLM format for history replay.
      # @param tool_calls [Array<Hash>, nil] tool calls in OpenAI-style format
      # @return [Hash{String => ToolCallProxy}, nil] tool calls keyed by ID
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
