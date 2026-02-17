# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Conversation', :integration do
  shared_examples 'conversation scenarios' do |provider_label:|
    let(:agent) { create_integration_agent(provider: @provider, workspace: @workspace) }

    it "responds to a greeting [#{provider_label}]", scenario: :simple_greeting do
      response = agent_send('Say hello in exactly one sentence.')
      expect(response).to be_a(String)
      expect(response.strip.length).to be > 0
    end

    it "answers a factual question [#{provider_label}]", scenario: :factual_question do
      response = agent_send('What is 2 + 2? Reply with just the number.')
      expect(response).to match(/4/)
    end

    it "maintains context across turns [#{provider_label}]", scenario: :multi_turn do
      agent_send('Remember this code: ALPHA-9923. I will ask about it later.')
      response = agent_send('What was the code I asked you to remember?')
      expect(response).to include('ALPHA-9923')
    end
  end

  Nanobot::Integration::DSL.include_scenarios(self, 'conversation scenarios')
end
