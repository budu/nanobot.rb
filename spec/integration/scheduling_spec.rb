# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Scheduling', :integration do
  shared_examples 'scheduling scenarios' do |provider_label:|
    let(:schedule_store_path) { File.join(@workspace, 'schedules.json') }
    let(:schedule_store) { Nanobot::Scheduler::ScheduleStore.new(path: schedule_store_path) }
    let(:agent) do
      create_integration_agent(provider: @provider, workspace: @workspace, schedule_store: schedule_store)
    end

    it "creates a schedule when asked [#{provider_label}]", scenario: :tool_schedule_add do
      response = agent_send(
        'Set a reminder for 30 minutes from now to check my email. ' \
        'Use the schedule_add tool with kind "every" and expression "30m".'
      )
      expect(response).to be_a(String)
      expect(schedule_store.list.size).to eq(1)
      expect(schedule_store.list.first.kind).to eq('every')
      expect(schedule_store.list.first.expression).to eq('30m')
    end

    it "lists schedules when asked [#{provider_label}]", scenario: :tool_schedule_list do
      schedule_store.add(kind: 'cron', expression: '0 9 * * *', prompt: 'morning standup reminder')
      response = agent_send('List all my scheduled tasks.')
      expect(response).to include('morning standup')
    end

    it "removes a schedule when asked [#{provider_label}]", scenario: :tool_schedule_remove do
      schedule_store.add(kind: 'every', expression: '2h', prompt: 'check server status')
      response = agent_send(
        'List my scheduled tasks, then remove all of them. ' \
        'Use schedule_list first, then schedule_remove for each task.'
      )
      expect(response).to be_a(String)
      expect(response).to match(/remove|delet|clear/i)
    end
  end

  Nanobot::Integration::DSL.include_scenarios(self, 'scheduling scenarios')
end
