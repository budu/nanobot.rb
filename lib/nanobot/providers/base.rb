# frozen_string_literal: true

module Nanobot
  module Providers
    # ToolCallRequest represents a tool call from the LLM
    ToolCallRequest = Struct.new(:id, :name, :arguments, keyword_init: true)

    # LLMResponse represents the response from an LLM
    LLMResponse = Struct.new(:content, :tool_calls, :finish_reason, keyword_init: true) do
      def initialize(content: nil, tool_calls: nil, finish_reason: nil)
        super(
          content: content || '',
          tool_calls: tool_calls || [],
          finish_reason: finish_reason
        )
      end

      def tool_calls?
        tool_calls && !tool_calls.empty?
      end
    end

    # Base class for LLM providers
    class LLMProvider
      # Chat with the LLM
      # @param messages [Array<Hash>] array of message hashes with :role and :content
      # @param tools [Array<Hash>] array of tool definitions in OpenAI format
      # @param model [String] model identifier
      # @param max_tokens [Integer] maximum tokens to generate
      # @param temperature [Float] sampling temperature
      # @return [LLMResponse]
      def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
        raise NotImplementedError, "#{self.class} must implement #chat"
      end

      # Get the default model for this provider
      # @return [String]
      def default_model
        raise NotImplementedError, "#{self.class} must implement #default_model"
      end
    end
  end
end
