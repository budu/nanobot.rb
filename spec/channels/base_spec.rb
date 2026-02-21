# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Channels::BaseChannel do
  let(:config) { double('config', allow_from: []) }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }

  let(:channel) do
    described_class.new(
      name: 'test',
      config: config,
      bus: bus,
      logger: logger
    )
  end

  describe '#initialize' do
    it 'initializes with required parameters' do
      expect(channel.name).to eq('test')
      expect(channel.config).to eq(config)
      expect(channel.bus).to eq(bus)
      expect(channel.logger).to eq(logger)
    end

    it 'starts in not running state' do
      expect(channel.running?).to be false
    end
  end

  describe '#start' do
    it 'raises NotImplementedError' do
      expect { channel.start }.to raise_error(NotImplementedError)
    end
  end

  describe '#stop' do
    it 'raises NotImplementedError' do
      expect { channel.stop }.to raise_error(NotImplementedError)
    end
  end

  describe '#send' do
    it 'raises NotImplementedError' do
      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'test',
        chat_id: 'chat1',
        content: 'test'
      )
      expect { channel.send(message) }.to raise_error(NotImplementedError)
    end
  end

  describe '#allowed?' do
    context 'with empty allow_from list' do
      it 'denies all senders' do
        expect(channel.allowed?('user1')).to be false
        expect(channel.allowed?('user2')).to be false
      end
    end

    context 'with wildcard allow_from' do
      let(:config) { double('config', allow_from: ['*']) }

      it 'allows all senders' do
        expect(channel.allowed?('user1')).to be true
        expect(channel.allowed?('anyone')).to be true
      end
    end

    context 'with allow_from whitelist' do
      let(:config) { double('config', allow_from: %w[user1 user2]) }

      it 'allows whitelisted senders' do
        expect(channel.allowed?('user1')).to be true
        expect(channel.allowed?('user2')).to be true
      end

      it 'denies non-whitelisted senders' do
        expect(channel.allowed?('user3')).to be false
      end

      it 'handles numeric sender IDs' do
        config = double('config', allow_from: %w[123])
        channel = described_class.new(
          name: 'test',
          config: config,
          bus: bus,
          logger: logger
        )
        expect(channel.allowed?(123)).to be true
      end
    end
  end

  describe '#running?' do
    it 'returns running state' do
      expect(channel.running?).to be false

      channel.instance_variable_set(:@running, true)
      expect(channel.running?).to be true
    end
  end

  describe 'protected method #handle_message' do
    # Create a test subclass to access protected method
    let(:test_channel_class) do
      Class.new(described_class) do
        def start; end
        def stop; end
        def send(message); end

        def test_handle_message(**)
          handle_message(**)
        end
      end
    end

    let(:open_config) { double('config', allow_from: ['*']) }

    let(:test_channel) do
      test_channel_class.new(name: 'test', config: open_config, bus: bus, logger: logger)
    end

    let(:message_params) do
      {
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Hello',
        media: []
      }
    end

    it 'publishes inbound message to bus' do
      allow(bus).to receive(:publish_inbound)

      test_channel.test_handle_message(**message_params)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg).to be_a(Nanobot::Bus::InboundMessage)
        expect(msg.channel).to eq('test')
        expect(msg.sender_id).to eq('user1')
        expect(msg.chat_id).to eq('chat1')
        expect(msg.content).to eq('Hello')
      end
    end

    it 'logs received message' do
      allow(bus).to receive(:publish_inbound)
      allow(logger).to receive(:debug)

      test_channel.test_handle_message(**message_params)

      expect(logger).to have_received(:debug).with('Received message from test:chat1')
    end

    context 'with access control' do
      let(:config) { double('config', allow_from: ['user1']) }
      let(:test_channel) do
        test_channel_class.new(name: 'test', config: config, bus: bus, logger: logger)
      end

      it 'allows authorized senders' do
        allow(bus).to receive(:publish_inbound)

        test_channel.test_handle_message(**message_params)

        expect(bus).to have_received(:publish_inbound)
      end

      it 'blocks unauthorized senders' do
        allow(bus).to receive(:publish_inbound)
        allow(logger).to receive(:warn)

        test_channel.test_handle_message(sender_id: 'user2', chat_id: 'chat1', content: 'Hello')

        expect(bus).not_to have_received(:publish_inbound)
        expect(logger).to have_received(:warn).with('Access denied for user2 on channel test')
      end
    end

    it 'handles media attachments' do
      allow(bus).to receive(:publish_inbound)

      test_channel.test_handle_message(
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Check this out',
        media: ['image.jpg', 'video.mp4']
      )

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg.media).to eq(['image.jpg', 'video.mp4'])
      end
    end
  end
end
