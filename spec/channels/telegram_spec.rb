# frozen_string_literal: true

require 'spec_helper'

# Create stub Telegram classes for testing without the gem
unless defined?(Telegram::Bot)
  module Telegram
    module Bot
      module Types
        class Message
          attr_accessor :text, :chat, :from
        end
      end

      class Client
        def self.run(_token, &); end
      end
    end
  end
end

# Load the channel after stubs are in place
require 'nanobot/channels/telegram'

RSpec.describe Nanobot::Channels::Telegram do
  let(:config) { double('config', token: 'test-token', allow_from: []) }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }

  let(:bot_api) { double('api') }
  let(:bot) { double('bot', api: bot_api) }

  let(:channel) do
    described_class.new(
      name: 'telegram',
      config: config,
      bus: bus,
      logger: logger
    )
  end

  describe '#initialize' do
    it 'initializes with required parameters' do
      expect(channel.name).to eq('telegram')
      expect(channel.config).to eq(config)
      expect(channel.bus).to eq(bus)
      expect(channel.logger).to eq(logger)
    end

    it 'starts in not running state' do
      expect(channel.running?).to be false
    end
  end

  describe '#start' do
    let(:tg_chat) { double('chat', id: 12_345) }
    let(:tg_from) { double('from', id: 67_890) }

    let(:tg_message) do
      msg = Telegram::Bot::Types::Message.new
      msg.text = 'Hello bot'
      msg.chat = tg_chat
      msg.from = tg_from
      msg
    end

    before do
      allow(bot_api).to receive(:set_my_commands)
      allow(bot_api).to receive(:send_chat_action)
      allow(bus).to receive(:publish_inbound)
    end

    it 'sets running to true' do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen)

      channel.start

      expect(channel.running?).to be true
    end

    it 'registers commands on start' do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen)

      channel.start

      expect(bot_api).to have_received(:set_my_commands).with(commands: [
                                                                { command: 'new', description: 'Start a new session' },
                                                                { command: 'help', description: 'Show help' }
                                                              ])
    end

    it 'handles incoming text messages' do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(tg_message)

      channel.start

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg).to be_a(Nanobot::Bus::InboundMessage)
        expect(msg.channel).to eq('telegram')
        expect(msg.sender_id).to eq('67890')
        expect(msg.chat_id).to eq('12345')
        expect(msg.content).to eq('Hello bot')
      end
    end

    it 'skips non-Message objects' do
      update = double('update')
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(update)

      channel.start

      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'skips messages without text' do
      msg = Telegram::Bot::Types::Message.new
      msg.text = nil
      msg.chat = tg_chat
      msg.from = tg_from

      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(msg)

      channel.start

      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'starts typing indicator on incoming message' do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(tg_message)

      channel.start

      # Give the typing thread a moment to fire
      sleep 0.05

      expect(bot_api).to have_received(:send_chat_action).with(chat_id: '12345', action: 'typing').at_least(:once)
    end

    it 'breaks out of listen loop when not running' do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen) do |&block|
        channel.stop
        block.call(tg_message)
      end

      channel.start

      expect(bus).not_to have_received(:publish_inbound)
    end
  end

  describe '#stop' do
    it 'sets running to false' do
      channel.instance_variable_set(:@running, true)
      channel.stop
      expect(channel.running?).to be false
    end
  end

  describe '#send' do
    let(:message) do
      Nanobot::Bus::OutboundMessage.new(
        channel: 'telegram',
        chat_id: '12345',
        content: 'Hello user'
      )
    end

    before do
      channel.instance_variable_set(:@bot, bot)
    end

    it 'sends message via bot API' do
      allow(bot_api).to receive(:send_message)

      channel.send(message)

      expect(bot_api).to have_received(:send_message).with(chat_id: '12345', text: 'Hello user')
    end

    it 'does nothing when bot is not set' do
      channel.instance_variable_set(:@bot, nil)

      expect { channel.send(message) }.not_to raise_error
    end

    it 'stops typing indicator before sending' do
      allow(bot_api).to receive(:send_message)

      typing_thread = double('thread')
      allow(typing_thread).to receive(:kill)
      channel.instance_variable_set(:@typing_threads, { '12345' => typing_thread })

      channel.send(message)

      expect(typing_thread).to have_received(:kill)
    end

    it 'splits long messages into 4096-char chunks' do
      allow(bot_api).to receive(:send_message)

      long_content = 'a' * 8192
      long_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'telegram',
        chat_id: '12345',
        content: long_content
      )

      channel.send(long_message)

      expect(bot_api).to have_received(:send_message).exactly(2).times
      expect(bot_api).to have_received(:send_message).with(chat_id: '12345', text: 'a' * 4096).twice
    end

    it 'handles empty content' do
      allow(bot_api).to receive(:send_message)

      empty_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'telegram',
        chat_id: '12345',
        content: ''
      )

      channel.send(empty_message)

      expect(bot_api).to have_received(:send_message).with(chat_id: '12345', text: '').once
    end

    it 'handles nil content' do
      allow(bot_api).to receive(:send_message)

      nil_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'telegram',
        chat_id: '12345',
        content: nil
      )

      channel.send(nil_message)

      expect(bot_api).to have_received(:send_message).with(chat_id: '12345', text: '').once
    end
  end

  describe 'ACL filtering' do
    let(:config) { double('config', token: 'test-token', allow_from: ['67890']) }
    let(:tg_chat) { double('chat', id: 12_345) }

    before do
      allow(bot_api).to receive(:set_my_commands)
      allow(bot_api).to receive(:send_chat_action)
    end

    it 'allows messages from whitelisted senders' do
      tg_from = double('from', id: 67_890)
      msg = Telegram::Bot::Types::Message.new
      msg.text = 'Hello'
      msg.chat = tg_chat
      msg.from = tg_from

      allow(bus).to receive(:publish_inbound)
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(msg)

      channel.start

      expect(bus).to have_received(:publish_inbound)
    end

    it 'blocks messages from non-whitelisted senders' do
      tg_from = double('from', id: 99_999)
      msg = Telegram::Bot::Types::Message.new
      msg.text = 'Hello'
      msg.chat = tg_chat
      msg.from = tg_from

      allow(bus).to receive(:publish_inbound)
      allow(logger).to receive(:warn)
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(msg)

      channel.start

      expect(bus).not_to have_received(:publish_inbound)
    end
  end

  describe 'register_commands error handling' do
    it 'logs warning when command registration fails' do
      allow(bot_api).to receive(:set_my_commands).and_raise(StandardError, 'API error')
      allow(logger).to receive(:warn)
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen)

      channel.start

      expect(logger).to have_received(:warn).with('Failed to register Telegram commands: API error')
    end
  end

  describe 'split_message' do
    it 'splits text at exact character boundary' do
      # Access private method for unit testing
      result = channel.__send__(:split_message, 'abcdef', 3)
      expect(result).to eq(%w[abc def])
    end

    it 'returns single chunk for short text' do
      result = channel.__send__(:split_message, 'hello', 4096)
      expect(result).to eq(['hello'])
    end

    it 'returns empty string for nil' do
      result = channel.__send__(:split_message, nil, 4096)
      expect(result).to eq([''])
    end

    it 'returns empty string for empty text' do
      result = channel.__send__(:split_message, '', 4096)
      expect(result).to eq([''])
    end
  end

  describe 'typing indicators' do
    before do
      channel.instance_variable_set(:@bot, bot)
      allow(bot_api).to receive(:send_chat_action)
    end

    it 'starts typing thread for a chat' do
      channel.__send__(:start_typing, '12345')
      sleep 0.05

      expect(bot_api).to have_received(:send_chat_action).with(chat_id: '12345', action: 'typing').at_least(:once)

      # Clean up
      channel.__send__(:stop_typing, '12345')
    end

    it 'replaces existing typing thread for same chat' do
      channel.__send__(:start_typing, '12345')
      first_thread = channel.instance_variable_get(:@typing_threads)['12345']

      channel.__send__(:start_typing, '12345')
      second_thread = channel.instance_variable_get(:@typing_threads)['12345']

      expect(first_thread).not_to eq(second_thread)

      # Clean up
      channel.__send__(:stop_typing, '12345')
    end

    it 'stops typing by killing and removing thread' do
      channel.__send__(:start_typing, '12345')
      expect(channel.instance_variable_get(:@typing_threads)).to have_key('12345')

      channel.__send__(:stop_typing, '12345')
      expect(channel.instance_variable_get(:@typing_threads)).not_to have_key('12345')
    end

    it 'handles stop_typing when no threads exist' do
      expect { channel.__send__(:stop_typing, '99999') }.not_to raise_error
    end
  end
end
