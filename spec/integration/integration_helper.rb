# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'

module Nanobot
  module Integration
    FIXTURES_DIR = File.expand_path('../fixtures/integration_responses', __dir__)

    # Environment-based configuration for integration tests
    module Config
      def self.record_mode?
        ENV['NANOBOT_INTEGRATION_RECORD'] == 'true'
      end

      def self.provider_name
        ENV.fetch('NANOBOT_INTEGRATION_PROVIDER', 'anthropic')
      end

      def self.model_name
        ENV.fetch('NANOBOT_INTEGRATION_MODEL', 'claude-haiku-4-5')
      end

      def self.slugify(name)
        name.gsub('/', '-').gsub(/[^a-zA-Z0-9._-]/, '-')
      end

      def self.fixture_filename
        slug = "#{slugify(provider_name)}_#{slugify(model_name)}_#{Time.now.strftime('%Y%m%dT%H%M%S')}"
        "#{slug}.json"
      end

      def self.fixture_files
        Dir.glob(File.join(FIXTURES_DIR, '*.json'))
      end
    end

    # Wraps a real provider, recording every LLMResponse per scenario
    class RecordingProvider < Providers::LLMProvider
      attr_reader :scenarios

      def initialize(real_provider)
        super()
        @real_provider = real_provider
        @scenarios = {}
        @workspaces = {}
        @current_scenario = nil
      end

      def default_model
        @real_provider.default_model
      end

      attr_writer :current_workspace

      def start_scenario(name)
        @current_scenario = name
        @scenarios[name] = []
      end

      def finish_scenario
        @workspaces[@current_scenario] = @current_workspace if @current_scenario
        @current_scenario = nil
      end

      def chat(messages:, tools: nil, model: nil, max_tokens: 4096, temperature: 0.7)
        response = @real_provider.chat(
          messages: messages, tools: tools, model: model,
          max_tokens: max_tokens, temperature: temperature
        )

        @scenarios[@current_scenario] << serialize_response(response) if @current_scenario

        response
      end

      def save_fixture
        FileUtils.mkdir_p(FIXTURES_DIR)
        path = File.join(FIXTURES_DIR, Config.fixture_filename)

        data = {
          metadata: {
            provider: Config.provider_name,
            model: Config.model_name,
            recorded_at: Time.now.utc.iso8601,
            nanobot_version: Nanobot::VERSION
          },
          scenarios: @scenarios.transform_values.with_index { |responses, _i| responses },
          workspaces: @workspaces
        }

        File.write(path, JSON.pretty_generate(data))
        path
      end

      private

      def serialize_response(response)
        {
          content: response.content,
          tool_calls: response.tool_calls.map { |tc| serialize_tool_call(tc) },
          finish_reason: response.finish_reason
        }
      end

      def serialize_tool_call(tc)
        { id: tc.id, name: tc.name, arguments: tc.arguments }
      end
    end

    # Replays recorded responses in sequence, per scenario
    class ReplayProvider < Providers::LLMProvider
      attr_reader :metadata

      def initialize(fixture_path)
        super()
        data = JSON.parse(File.read(fixture_path), symbolize_names: true)
        @metadata = data[:metadata]
        @raw_scenarios = data[:scenarios]
        @workspaces = data[:workspaces] || {}
        @current_raw_responses = []
        @current_workspace = nil
      end

      attr_writer :current_workspace

      def default_model
        @metadata[:model]
      end

      def start_scenario(name)
        key = find_scenario_key(name)
        @current_raw_responses = key ? @raw_scenarios[key].dup : []
        @recorded_workspace = key ? @workspaces[key] : nil
      end

      def finish_scenario
        @current_raw_responses = []
        @recorded_workspace = nil
        @current_workspace = nil
      end

      def scenario?(name)
        !find_scenario_key(name).nil?
      end

      def chat(**_kwargs)
        if @current_raw_responses.empty?
          raise 'ReplayProvider: no more recorded responses for current scenario. ' \
                'The agent made more LLM calls than were recorded.'
        end

        deserialize_response(@current_raw_responses.shift, @recorded_workspace)
      end

      private

      def find_scenario_key(name)
        sym = name.to_sym
        str = name.to_s
        return sym if @raw_scenarios.key?(sym)
        return str if @raw_scenarios.key?(str)

        nil
      end

      def deserialize_response(data, recorded_workspace)
        tool_calls = (data[:tool_calls] || []).map do |tc|
          args = deep_symbolize_keys(tc[:arguments])
          args = rewrite_paths(args, recorded_workspace) if recorded_workspace && @current_workspace

          Providers::ToolCallRequest.new(id: tc[:id], name: tc[:name], arguments: args)
        end

        Providers::LLMResponse.new(
          content: data[:content],
          tool_calls: tool_calls,
          finish_reason: data[:finish_reason]
        )
      end

      # Replace recorded workspace paths with the current test workspace
      def rewrite_paths(obj, recorded_workspace)
        recorded = recorded_workspace.to_s
        current = @current_workspace.to_s
        return obj if recorded.empty?

        case obj
        when Hash
          obj.transform_values { |v| rewrite_paths(v, recorded_workspace) }
        when String
          obj.include?(recorded) ? obj.gsub(recorded, current) : obj
        when Array
          obj.map { |v| rewrite_paths(v, recorded_workspace) }
        else
          obj
        end
      end

      def deep_symbolize_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize_keys(v) }
        when Array
          obj.map { |v| deep_symbolize_keys(v) }
        else
          obj
        end
      end
    end

    # Helper methods available in integration specs
    module Helpers
      def create_integration_agent(provider:, workspace:, schedule_store: nil)
        @integration_chat_id = "integration-#{SecureRandom.hex(8)}"
        provider.current_workspace = workspace if provider.respond_to?(:current_workspace=)
        bus = Bus::MessageBus.new(logger: test_logger)
        Agent::Loop.new(
          bus: bus,
          provider: provider,
          workspace: workspace,
          model: provider.default_model,
          max_iterations: 10,
          restrict_to_workspace: true,
          schedule_store: schedule_store,
          logger: test_logger
        )
      end

      # Send a message through the agent with an isolated session
      def agent_send(content)
        agent.process_direct(content, chat_id: @integration_chat_id)
      end

      def workspace_path(relative)
        File.join(@workspace, relative)
      end
    end
  end
end

RSpec.configure do |config|
  config.include Nanobot::Integration::Helpers, :integration

  # Allow real HTTP connections when recording against a live LLM provider
  config.before(:suite) do
    WebMock.allow_net_connect! if Nanobot::Integration::Config.record_mode?
  end

  # Start scenario tracking before each example
  config.before(:each, :integration) do |example|
    scenario_key = example.metadata[:scenario]
    next unless scenario_key

    # Skip scenarios not present in the replay fixture
    if @provider.respond_to?(:scenario?) && !@provider.scenario?(scenario_key.to_s)
      skip "Scenario '#{scenario_key}' not recorded in fixture (re-record to include)"
    end

    @provider.start_scenario(scenario_key.to_s) if @provider.respond_to?(:start_scenario)
  end

  config.after(:each, :integration) do |example|
    next unless example.metadata[:scenario]

    @provider.finish_scenario if @provider.respond_to?(:finish_scenario)
  end
end
