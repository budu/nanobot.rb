# frozen_string_literal: true

require 'spec_helper'

# Stub Discordrb module for testing without the gem
unless defined?(Discordrb)
  module Discordrb
    class Bot
      def initialize(**); end

      def message(&); end

      def run; end

      def stop; end

      def channel(id); end
    end
  end
end

require 'nanobot/channels/discord'

RSpec.describe Nanobot::Channels::Discord do
  let(:config) { double('config', token: 'test-token', allow_from: []) }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }
  let(:bot) { double('bot') }

  let(:channel) do
    described_class.new(
      name: 'discord',
      config: config,
      bus: bus,
      logger: logger
    )
  end

  describe '#initialize' do
    it 'starts in not running state' do
      expect(channel.running?).to be false
    end

    it 'stores the configuration' do
      expect(channel.config).to eq(config)
    end
  end

  describe '#start' do
    let(:message_handler) { nil }

    before do
      allow(Discordrb::Bot).to receive(:new).and_return(bot)
      allow(bot).to receive(:message) { |&block| @message_handler = block }
      allow(bot).to receive(:run)
    end

    it 'creates a bot with the configured token' do
      channel.start

      expect(Discordrb::Bot).to have_received(:new).with(token: 'test-token', intents: [:server_messages])
    end

    it 'sets running to true' do
      channel.start

      expect(channel.running?).to be true
    end

    it 'registers a message handler' do
      channel.start

      expect(bot).to have_received(:message)
    end

    it 'calls bot.run' do
      channel.start

      expect(bot).to have_received(:run)
    end

    context 'when receiving a message' do
      let(:author) { double('author', id: 12_345, bot_account?: false) }
      let(:discord_channel) { double('channel', id: 67_890) }
      let(:event) { double('event', author: author, channel: discord_channel, content: 'Hello') }
      let(:message_handler) { @message_handler } # rubocop:disable RSpec/InstanceVariable

      before do
        allow(bus).to receive(:publish_inbound)
        channel.start
      end

      it 'publishes the message to the bus' do
        message_handler.call(event)

        expect(bus).to have_received(:publish_inbound) do |msg|
          expect(msg).to be_a(Nanobot::Bus::InboundMessage)
          expect(msg.channel).to eq('discord')
          expect(msg.sender_id).to eq('12345')
          expect(msg.chat_id).to eq('67890')
          expect(msg.content).to eq('Hello')
        end
      end

      it 'skips bot messages' do
        bot_author = double('bot_author', id: 99_999, bot_account?: true)
        bot_event = double('bot_event', author: bot_author, channel: discord_channel, content: 'Bot message')

        message_handler.call(bot_event)

        expect(bus).not_to have_received(:publish_inbound)
      end

      it 'allows whitelisted senders with ACL' do
        allow(config).to receive(:allow_from).and_return(['12345'])

        message_handler.call(event)

        expect(bus).to have_received(:publish_inbound)
      end

      it 'blocks non-whitelisted senders with ACL' do
        allow(config).to receive(:allow_from).and_return(['12345'])
        blocked_author = double('author', id: 99_999, bot_account?: false)
        blocked_event = double('event', author: blocked_author, channel: discord_channel, content: 'Blocked')

        message_handler.call(blocked_event)

        expect(bus).not_to have_received(:publish_inbound)
      end
    end
  end

  describe '#stop' do
    before do
      allow(Discordrb::Bot).to receive(:new).and_return(bot)
      allow(bot).to receive(:message)
      allow(bot).to receive(:run)
      allow(bot).to receive(:stop)
    end

    it 'sets running to false' do
      channel.start
      channel.stop

      expect(channel.running?).to be false
    end

    it 'stops the bot' do
      channel.start
      channel.stop

      expect(bot).to have_received(:stop)
    end

    it 'handles stop when bot is nil' do
      expect { channel.stop }.not_to raise_error
    end
  end

  describe '#send' do
    let(:discord_channel_obj) { double('discord_channel') }

    before do
      allow(Discordrb::Bot).to receive(:new).and_return(bot)
      allow(bot).to receive(:message)
      allow(bot).to receive(:run)
      channel.start
    end

    it 'sends a message to the correct channel' do
      allow(bot).to receive(:channel).with(67_890).and_return(discord_channel_obj)
      allow(discord_channel_obj).to receive(:send_message)

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: 'Hello Discord!'
      )

      channel.send(message)

      expect(bot).to have_received(:channel).with(67_890)
      expect(discord_channel_obj).to have_received(:send_message).with('Hello Discord!')
    end

    it 'does nothing when bot is nil' do
      no_bot_channel = described_class.new(
        name: 'discord',
        config: config,
        bus: bus,
        logger: logger
      )

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: 'Hello'
      )

      expect { no_bot_channel.send(message) }.not_to raise_error
    end

    it 'does nothing when channel is not found' do
      allow(bot).to receive(:channel).with(67_890).and_return(nil)

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: 'Hello'
      )

      expect { channel.send(message) }.not_to raise_error
    end

    it 'splits long messages at 2000 characters' do
      allow(bot).to receive(:channel).with(67_890).and_return(discord_channel_obj)
      allow(discord_channel_obj).to receive(:send_message)

      long_content = 'a' * 4500
      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: long_content
      )

      channel.send(message)

      expect(discord_channel_obj).to have_received(:send_message).exactly(3).times
      expect(discord_channel_obj).to have_received(:send_message).with('a' * 2000).twice
      expect(discord_channel_obj).to have_received(:send_message).with('a' * 500).once
    end

    it 'handles empty content' do
      allow(bot).to receive(:channel).with(67_890).and_return(discord_channel_obj)
      allow(discord_channel_obj).to receive(:send_message)

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: ''
      )

      channel.send(message)

      expect(discord_channel_obj).to have_received(:send_message).with('').once
    end

    it 'handles nil content' do
      allow(bot).to receive(:channel).with(67_890).and_return(discord_channel_obj)
      allow(discord_channel_obj).to receive(:send_message)

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'discord',
        chat_id: '67890',
        content: nil
      )

      channel.send(message)

      expect(discord_channel_obj).to have_received(:send_message).with('').once
    end
  end
end
