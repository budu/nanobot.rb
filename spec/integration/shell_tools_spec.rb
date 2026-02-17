# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Shell tools', :integration do
  shared_examples 'shell tool scenarios' do |provider_label:|
    let(:agent) { create_integration_agent(provider: @provider, workspace: @workspace) }

    it "runs a command and reports output [#{provider_label}]", scenario: :tool_exec do
      response = agent_send('Run the command "echo nanobot_exec_test_8675" and tell me the output.')
      expect(response).to include('nanobot_exec_test_8675')
    end
  end

  Nanobot::Integration::DSL.include_scenarios(self, 'shell tool scenarios')
end
