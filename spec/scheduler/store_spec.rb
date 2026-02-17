# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Nanobot::Scheduler::ScheduleStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:store_path) { File.join(tmpdir, 'schedules.json') }
  let(:store) { described_class.new(path: store_path) }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#add' do
    it 'creates an "at" schedule with a future timestamp' do
      future = (Time.now + 3600).iso8601
      schedule = store.add(kind: 'at', expression: future, prompt: 'do something')

      expect(schedule.id).to match(/\A[0-9a-f-]{36}\z/)
      expect(schedule.kind).to eq('at')
      expect(schedule.expression).to eq(future)
      expect(schedule.prompt).to eq('do something')
      expect(schedule.enabled).to be true
      expect(schedule.next_run_at).not_to be_nil
    end

    it 'creates an "every" schedule with a duration' do
      schedule = store.add(kind: 'every', expression: '30m', prompt: 'check email')

      expect(schedule.kind).to eq('every')
      expect(schedule.expression).to eq('30m')
      next_run = Time.iso8601(schedule.next_run_at)
      expect(next_run).to be_within(5).of(Time.now + 1800)
    end

    it 'creates a "cron" schedule' do
      schedule = store.add(kind: 'cron', expression: '0 8 * * *', prompt: 'morning summary')

      expect(schedule.kind).to eq('cron')
      expect(schedule.expression).to eq('0 8 * * *')
      expect(schedule.next_run_at).not_to be_nil
    end

    it 'creates a "cron" schedule with timezone' do
      schedule = store.add(
        kind: 'cron', expression: '0 8 * * *',
        prompt: 'morning', timezone: 'America/New_York'
      )

      expect(schedule.timezone).to eq('America/New_York')
      expect(schedule.next_run_at).not_to be_nil
    end

    it 'stores deliver_to metadata' do
      schedule = store.add(
        kind: 'every', expression: '1h', prompt: 'notify',
        deliver_to: { channel: 'slack', chat_id: 'C123' }
      )

      expect(schedule.deliver_to).to eq({ channel: 'slack', chat_id: 'C123' })
    end

    it 'rejects invalid kind' do
      expect do
        store.add(kind: 'invalid', expression: '1h', prompt: 'test')
      end.to raise_error(ArgumentError, /Invalid schedule kind/)
    end

    it 'rejects invalid cron expression' do
      expect do
        store.add(kind: 'cron', expression: 'not a cron', prompt: 'test')
      end.to raise_error(ArgumentError, /Invalid cron expression/)
    end

    it 'rejects invalid duration expression' do
      expect do
        store.add(kind: 'every', expression: 'not a duration', prompt: 'test')
      end.to raise_error(ArgumentError, /Invalid duration expression/)
    end

    it 'rejects invalid ISO 8601 timestamp' do
      expect do
        store.add(kind: 'at', expression: 'not a timestamp', prompt: 'test')
      end.to raise_error(ArgumentError)
    end
  end

  describe '#get' do
    it 'returns a schedule by ID' do
      schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
      found = store.get(schedule.id)

      expect(found).not_to be_nil
      expect(found.id).to eq(schedule.id)
    end

    it 'returns nil for unknown ID' do
      expect(store.get('nonexistent')).to be_nil
    end
  end

  describe '#list' do
    it 'returns empty array when no schedules' do
      expect(store.list).to eq([])
    end

    it 'returns all schedules' do
      store.add(kind: 'every', expression: '1h', prompt: 'first')
      store.add(kind: 'every', expression: '2h', prompt: 'second')

      expect(store.list.size).to eq(2)
    end
  end

  describe '#remove' do
    it 'removes an existing schedule' do
      schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')

      expect(store.remove(schedule.id)).to be true
      expect(store.get(schedule.id)).to be_nil
      expect(store.list).to be_empty
    end

    it 'returns false for unknown ID' do
      expect(store.remove('nonexistent')).to be false
    end
  end

  describe '#update' do
    it 'updates specific fields' do
      schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
      updated = store.update(schedule.id, enabled: false)

      expect(updated.enabled).to be false
      expect(store.get(schedule.id).enabled).to be false
    end

    it 'returns nil for unknown ID' do
      expect(store.update('nonexistent', enabled: false)).to be_nil
    end
  end

  describe '#due_schedules' do
    it 'returns schedules whose next_run_at is in the past' do
      Timecop.freeze(Time.now) do
        schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
        # Not due yet
        expect(store.due_schedules).to be_empty

        # Travel past the next_run_at
        Timecop.travel(Time.iso8601(schedule.next_run_at) + 1)
        expect(store.due_schedules.size).to eq(1)
        expect(store.due_schedules.first.id).to eq(schedule.id)
      end
    end

    it 'excludes disabled schedules' do
      Timecop.freeze(Time.now) do
        schedule = store.add(kind: 'every', expression: '1h', prompt: 'test')
        store.update(schedule.id, enabled: false)

        Timecop.travel(Time.iso8601(schedule.next_run_at) + 1)
        expect(store.due_schedules).to be_empty
      end
    end
  end

  describe '#advance!' do
    it 'disables "at" schedules after firing' do
      future = (Time.now + 3600).iso8601
      schedule = store.add(kind: 'at', expression: future, prompt: 'once')

      store.advance!(schedule)

      updated = store.get(schedule.id)
      expect(updated.enabled).to be false
      expect(updated.next_run_at).to be_nil
      expect(updated.last_run_at).not_to be_nil
    end

    it 'advances "every" schedules by the duration' do
      Timecop.freeze(Time.now) do
        schedule = store.add(kind: 'every', expression: '30m', prompt: 'recurring')
        now = Time.now

        store.advance!(schedule, now)

        updated = store.get(schedule.id)
        expect(updated.enabled).to be true
        next_run = Time.iso8601(updated.next_run_at)
        expect(next_run).to be_within(2).of(now + 1800)
      end
    end

    it 'advances "cron" schedules to the next cron time' do
      Timecop.freeze(Time.new(2026, 2, 17, 8, 0, 0)) do
        schedule = store.add(kind: 'cron', expression: '0 8 * * *', prompt: 'daily')

        store.advance!(schedule, Time.now)

        updated = store.get(schedule.id)
        expect(updated.enabled).to be true
        next_run = Time.iso8601(updated.next_run_at)
        # Should be tomorrow at 8am
        expect(next_run.hour).to eq(8)
        expect(next_run.day).to eq(18)
      end
    end
  end

  describe 'persistence' do
    it 'round-trips schedules through JSON' do
      store.add(kind: 'every', expression: '1h', prompt: 'persistent')
      store.add(kind: 'cron', expression: '0 9 * * *', prompt: 'daily check')

      # Load a new store from the same file
      reloaded = described_class.new(path: store_path)

      expect(reloaded.list.size).to eq(2)
      expect(reloaded.list.map(&:prompt)).to contain_exactly('persistent', 'daily check')
    end

    it 'persists deliver_to through round-trip' do
      store.add(
        kind: 'every', expression: '1h', prompt: 'notify',
        deliver_to: { channel: 'slack', chat_id: 'C123' }
      )

      reloaded = described_class.new(path: store_path)
      schedule = reloaded.list.first

      # After JSON round-trip, keys become strings
      expect(schedule.deliver_to['channel'] || schedule.deliver_to[:channel]).to eq('slack')
    end

    it 'handles missing file gracefully' do
      store = described_class.new(path: File.join(tmpdir, 'nonexistent.json'))
      expect(store.list).to be_empty
    end

    it 'handles corrupted file gracefully' do
      File.write(store_path, 'not valid json{{{')
      store = described_class.new(path: store_path)
      expect(store.list).to be_empty
    end
  end
end
