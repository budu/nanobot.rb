# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Channels::Manager do
  let(:config) { {} }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }
  let(:manager) { described_class.new(config: config, bus: bus, logger: logger) }

  describe '#initialize' do
    it 'initializes with config and bus' do
      expect(manager.bus).to eq(bus)
      expect(manager.logger).to eq(logger)
    end

    it 'starts with empty channels' do
      expect(manager.channels).to eq({})
    end
  end

  describe '#add_channel' do
    let(:channel) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'test_channel'
      )
    end

    it 'adds channel to manager' do
      manager.add_channel(channel)
      expect(manager.channels['test_channel']).to eq(channel)
    end

    it 'logs channel addition' do
      allow(logger).to receive(:info)
      manager.add_channel(channel)
      expect(logger).to have_received(:info).with('Added channel: test_channel')
    end
  end

  describe '#start_all' do
    let(:channel) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'test_channel',
        start: nil
      )
    end

    before do
      allow(bus).to receive(:subscribe_outbound)
      allow(bus).to receive(:start_dispatch)
      manager.add_channel(channel)
    end

    it 'subscribes to outbound messages for each channel' do
      manager.start_all
      expect(bus).to have_received(:subscribe_outbound).with('test_channel')
    end

    it 'starts bus dispatcher' do
      manager.start_all
      expect(bus).to have_received(:start_dispatch)
    end

    it 'starts each channel in separate thread' do
      allow(channel).to receive(:stop)
      allow(bus).to receive(:stop) # Add this mock
      manager.start_all
      sleep 0.1
      manager.stop_all
      # Verify that manager has threads
      expect(manager.instance_variable_get(:@threads)).not_to be_empty
    end

    it 'handles channel start errors' do
      allow(channel).to receive(:start).and_raise(StandardError.new('Start error'))
      allow(channel).to receive(:stop)
      allow(bus).to receive(:stop) # Add this mock
      allow(logger).to receive(:error)

      manager.start_all
      sleep 0.1
      manager.stop_all

      expect(logger).to have_received(:error).with(match(/Start error/))
    end

    it 'handles send errors in outbound subscription' do
      allow(bus).to receive(:subscribe_outbound).and_yield(
        Nanobot::Bus::OutboundMessage.new(
          channel: 'test_channel',
          chat_id: 'chat1',
          content: 'test'
        )
      )
      allow(channel).to receive(:send).and_raise(StandardError.new('Send error'))
      allow(logger).to receive(:error)

      manager.start_all

      expect(logger).to have_received(:error).with(match(/Send error/))
    end
  end

  describe '#stop_all' do
    let(:channel) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'test_channel',
        start: nil,
        stop: nil
      )
    end

    before do
      allow(bus).to receive(:subscribe_outbound)
      allow(bus).to receive(:start_dispatch)
      allow(bus).to receive(:stop)
      allow(channel).to receive(:stop)
      manager.add_channel(channel)
    end

    it 'stops all channels' do
      thread = Thread.new { manager.start_all }
      sleep 0.2
      manager.stop_all
      thread.join(1)

      expect(channel).to have_received(:stop)
    end

    it 'stops bus' do
      thread = Thread.new { manager.start_all }
      sleep 0.2
      manager.stop_all
      thread.join(1)

      expect(bus).to have_received(:stop)
    end

    it 'handles stop errors gracefully' do
      allow(channel).to receive(:stop).and_raise(StandardError.new('Stop error'))
      allow(logger).to receive(:error)

      thread = Thread.new { manager.start_all }
      sleep 0.2
      manager.stop_all
      thread.join(1)

      expect(logger).to have_received(:error).with(match(/Stop error/))
    end

    it 'waits for threads to finish' do
      manager.start_all
      sleep 0.1

      # Verify threads exist before stopping
      threads = manager.instance_variable_get(:@threads)
      expect(threads).not_to be_empty

      manager.stop_all

      # Threads should be stopped
      threads.each do |t|
        expect(t).not_to be_alive
      end
    end
  end

  describe '#get_channel' do
    let(:channel) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'test_channel'
      )
    end

    it 'returns channel by name' do
      manager.add_channel(channel)
      expect(manager.get_channel('test_channel')).to eq(channel)
    end

    it 'returns nil for non-existent channel' do
      expect(manager.get_channel('nonexistent')).to be_nil
    end
  end

  describe '#channel?' do
    let(:channel) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'test_channel'
      )
    end

    it 'returns true if channel exists' do
      manager.add_channel(channel)
      expect(manager.channel?('test_channel')).to be true
    end

    it 'returns false if channel does not exist' do
      expect(manager.channel?('nonexistent')).to be false
    end
  end

  describe '#size' do
    let(:channel1) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'channel1'
      )
    end

    let(:channel2) do
      instance_double(
        Nanobot::Channels::BaseChannel,
        name: 'channel2'
      )
    end

    it 'returns number of channels' do
      expect(manager.size).to eq(0)

      manager.add_channel(channel1)
      expect(manager.size).to eq(1)

      manager.add_channel(channel2)
      expect(manager.size).to eq(2)
    end
  end
end
