# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Slash commands', :integration do
  shared_examples 'slash command scenarios' do |provider_label:|
    let(:agent) { create_integration_agent(provider: @provider, workspace: @workspace) }

    it "handles /help command [#{provider_label}]", :skip_scenario_tracking do
      response = agent_send('/help')
      expect(response).to include('Available commands:')
      expect(response).to include('/new')
      expect(response).to include('/help')
    end

    it "handles /new command [#{provider_label}]", :skip_scenario_tracking do
      response = agent_send('/new')
      expect(response).to eq('New session started.')
    end
  end

  Nanobot::Integration::DSL.include_scenarios(self, 'slash command scenarios')
end
