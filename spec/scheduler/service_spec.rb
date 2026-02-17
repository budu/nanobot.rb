# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Nanobot::Scheduler::SchedulerService do
  let(:tmpdir) { Dir.mktmpdir }
  let(:store_path) { File.join(tmpdir, 'schedules.json') }
  let(:store) { Nanobot::Scheduler::ScheduleStore.new(path: store_path) }
  let(:bus) { Nanobot::Bus::MessageBus.new(logger: test_logger) }
  let(:logger) { test_logger }
  let(:service) { described_class.new(store: store, bus: bus, logger: logger, tick_interval: 0.05) }

  after do
    service.stop if service.running?
    bus.stop if bus.running?
    FileUtils.rm_rf(tmpdir)
  end

  describe '#start and #stop' do
    it 'starts and stops cleanly' do
      expect(service.running?).to be false

      service.start
      expect(service.running?).to be true

      service.stop
      expect(service.running?).to be false
    end
  end

  describe 'tick behavior' do
    it 'fires due schedules and publishes InboundMessage to bus' do
      # Create a schedule that is already due
      Timecop.freeze(Time.now) do
        store.add(kind: 'at', expression: (Time.now - 60).iso8601, prompt: 'hello from scheduler')
      end

      messages = []
      consumer_thread = Thread.new do
        msg = bus.consume_inbound(timeout: 2)
        messages << msg if msg
      end

      service.start
      consumer_thread.join(3)
      service.stop

      expect(messages.size).to eq(1)
      expect(messages.first.channel).to eq('scheduler')
      expect(messages.first.sender_id).to eq('scheduler')
      expect(messages.first.content).to eq('hello from scheduler')
      expect(messages.first.chat_id).to start_with('schedule:')
    end

    it 'advances the schedule after firing' do
      Timecop.freeze(Time.now) do
        schedule = store.add(kind: 'at', expression: (Time.now - 60).iso8601, prompt: 'once only')

        # Consume the message so the bus doesn't block
        consumer = Thread.new { bus.consume_inbound(timeout: 2) }

        service.start
        consumer.join(3)
        service.stop

        updated = store.get(schedule.id)
        expect(updated.enabled).to be false
        expect(updated.last_run_at).not_to be_nil
      end
    end

    it 'does not fire disabled schedules' do
      Timecop.freeze(Time.now) do
        schedule = store.add(kind: 'at', expression: (Time.now - 60).iso8601, prompt: 'disabled')
        store.update(schedule.id, enabled: false)
      end

      messages = []
      consumer = Thread.new do
        msg = bus.consume_inbound(timeout: 0.3)
        messages << msg if msg
      end

      service.start
      consumer.join(1)
      service.stop

      expect(messages).to be_empty
    end

    it 'continues running when a tick raises an error' do
      allow(store).to receive(:due_schedules).and_raise(StandardError, 'test error')

      service.start
      sleep 0.15 # Let a couple ticks pass
      expect(service.running?).to be true
      service.stop
    end
  end

  describe 'response routing' do
    it 'routes outbound scheduler messages to the deliver_to channel' do
      schedule = store.add(
        kind: 'at', expression: (Time.now - 60).iso8601,
        prompt: 'notify user',
        deliver_to: { channel: 'slack', chat_id: 'C123' }
      )

      routed_messages = []
      bus.subscribe_outbound('slack') do |msg|
        routed_messages << msg
      end
      bus.start_dispatch

      # Consume the inbound so it doesn't block, then simulate agent response
      consumer = Thread.new { bus.consume_inbound(timeout: 2) }

      service.start
      consumer.join(3)

      # Simulate the agent responding to the scheduler message
      bus.publish_outbound(
        Nanobot::Bus::OutboundMessage.new(
          channel: 'scheduler',
          chat_id: "schedule:#{schedule.id}",
          content: 'Here is your notification'
        )
      )

      sleep 0.1 # Let dispatch run
      service.stop
      bus.stop

      expect(routed_messages.size).to eq(1)
      expect(routed_messages.first.channel).to eq('slack')
      expect(routed_messages.first.chat_id).to eq('C123')
      expect(routed_messages.first.content).to eq('Here is your notification')
    end

    it 'discards outbound messages when no deliver_to is set' do
      store.add(
        kind: 'at', expression: (Time.now - 60).iso8601,
        prompt: 'fire and forget'
      )

      routed_messages = []
      bus.subscribe_outbound('slack') do |msg|
        routed_messages << msg
      end
      bus.start_dispatch

      consumer = Thread.new { bus.consume_inbound(timeout: 2) }

      service.start
      consumer.join(3)

      # Simulate response — should not route anywhere
      schedule = store.list.first
      bus.publish_outbound(
        Nanobot::Bus::OutboundMessage.new(
          channel: 'scheduler',
          chat_id: "schedule:#{schedule.id}",
          content: 'response'
        )
      )

      sleep 0.1
      service.stop
      bus.stop

      expect(routed_messages).to be_empty
    end
  end
end
