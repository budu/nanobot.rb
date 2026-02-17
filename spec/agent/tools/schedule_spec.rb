# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'nanobot/agent/tools/schedule'

RSpec.describe Nanobot::Agent::Tools do
  let(:tmpdir) { Dir.mktmpdir }
  let(:store_path) { File.join(tmpdir, 'schedules.json') }
  let(:store) { Nanobot::Scheduler::ScheduleStore.new(path: store_path) }

  after { FileUtils.rm_rf(tmpdir) }

  describe Nanobot::Agent::Tools::ScheduleAdd do
    let(:tool) { described_class.new(store: store) }

    it 'creates a schedule and returns confirmation' do
      future = (Time.now + 3600).iso8601
      result = tool.execute(kind: 'at', expression: future, prompt: 'remind me')

      expect(result).to include('Created schedule')
      expect(result).to include('at: ')
      expect(result).to include('Next run:')
      expect(store.list.size).to eq(1)
    end

    it 'creates a schedule with deliver_to' do
      result = tool.execute(
        kind: 'every', expression: '1h', prompt: 'check email',
        deliver_channel: 'slack', deliver_chat_id: 'C123'
      )

      expect(result).to include('Created schedule')
      schedule = store.list.first
      expect(schedule.deliver_to).to eq({ channel: 'slack', chat_id: 'C123' })
    end

    it 'does not set deliver_to when only channel is provided' do
      tool.execute(kind: 'every', expression: '1h', prompt: 'test', deliver_channel: 'slack')

      schedule = store.list.first
      expect(schedule.deliver_to).to be_nil
    end

    it 'returns error for invalid kind' do
      result = tool.execute(kind: 'bad', expression: '1h', prompt: 'test')
      expect(result).to include('Error creating schedule')
    end

    it 'returns error for invalid expression' do
      result = tool.execute(kind: 'cron', expression: 'not valid', prompt: 'test')
      expect(result).to include('Error creating schedule')
    end

    it 'creates a cron schedule with timezone' do
      result = tool.execute(
        kind: 'cron', expression: '0 8 * * *', prompt: 'morning',
        timezone: 'America/New_York'
      )

      expect(result).to include('Created schedule')
      schedule = store.list.first
      expect(schedule.timezone).to eq('America/New_York')
    end
  end

  describe Nanobot::Agent::Tools::ScheduleList do
    let(:tool) { described_class.new(store: store) }

    it 'returns message when no schedules exist' do
      result = tool.execute
      expect(result).to eq('No scheduled tasks.')
    end

    it 'lists all schedules with formatted output' do
      store.add(kind: 'every', expression: '1h', prompt: 'check email')
      store.add(kind: 'cron', expression: '0 8 * * *', prompt: 'morning summary')

      result = tool.execute

      expect(result).to include('Scheduled tasks (2)')
      expect(result).to include('every(1h)')
      expect(result).to include('cron(0 8 * * *)')
      expect(result).to include('check email')
      expect(result).to include('morning summary')
    end

    it 'truncates long prompts' do
      long_prompt = 'a' * 200
      store.add(kind: 'every', expression: '1h', prompt: long_prompt)

      result = tool.execute

      expect(result).to include('...')
      expect(result.length).to be < 300
    end
  end

  describe Nanobot::Agent::Tools::ScheduleRemove do
    let(:tool) { described_class.new(store: store) }

    it 'removes a schedule by full ID' do
      schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
      result = tool.execute(id: schedule.id)

      expect(result).to include('Removed schedule')
      expect(store.list).to be_empty
    end

    it 'removes a schedule by partial ID' do
      schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
      partial = schedule.id[0..7]
      result = tool.execute(id: partial)

      expect(result).to include('Removed schedule')
      expect(store.list).to be_empty
    end

    it 'returns not found for unknown ID' do
      result = tool.execute(id: 'nonexistent')
      expect(result).to include('Schedule not found')
    end
  end
end
