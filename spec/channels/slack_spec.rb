# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'

# Stub Slack module for testing without the gem
unless defined?(Slack::Web)
  module Slack
    def self.configure
      yield(Struct.new(:token).new) if block_given?
    end

    module Web
      class Client
        def initialize(**); end
        def auth_test = { 'user_id' => 'U12345' }
        def chat_postMessage(**); end # rubocop:disable Naming/MethodName
        def reactions_add(**); end
      end
    end

    module RealTime
      class Client
        def initialize(**); end
        def on(event, &); end
        def start!; end
        def stop!; end
      end
    end
  end
end

# Load the channel after stubs are in place
require 'nanobot/channels/slack'

RSpec.describe Nanobot::Channels::Slack do
  let(:dm_config) do
    Nanobot::Config::SlackDMConfig.new(enabled: true, policy: 'open', allow_from: [])
  end

  let(:config) do
    double(
      'config',
      bot_token: 'xoxb-test-token',
      app_token: 'xapp-test-token',
      group_policy: 'mention',
      group_allow_from: [],
      dm: dm_config
    )
  end

  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }
  let(:web_client) { instance_double(Slack::Web::Client) }

  let(:test_channel_class) do
    Class.new(described_class) do
      public :handle_slack_message, :allowed_slack?, :should_respond_in_channel?,
             :strip_bot_mention, :add_eyes_reaction
      attr_writer :bot_user_id, :web_client
    end
  end

  let(:channel) do
    ch = test_channel_class.new(
      name: 'slack',
      config: config,
      bus: bus,
      logger: logger
    )
    ch.bot_user_id = 'U12345'
    ch.web_client = web_client
    ch
  end

  describe '#initialize' do
    it 'initializes with required parameters' do
      expect(channel.name).to eq('slack')
      expect(channel.config).to eq(config)
      expect(channel.bus).to eq(bus)
      expect(channel.logger).to eq(logger)
    end

    it 'starts in not running state' do
      expect(channel.running?).to be false
    end
  end

  describe '#stop' do
    it 'sets running to false' do
      channel.instance_variable_set(:@running, true)
      channel.instance_variable_set(:@socket_client, double('socket', stop!: nil))
      channel.stop
      expect(channel.running?).to be false
    end

    it 'stops the socket client' do
      socket = double('socket')
      allow(socket).to receive(:stop!)
      channel.instance_variable_set(:@socket_client, socket)

      channel.stop

      expect(socket).to have_received(:stop!)
    end

    it 'handles nil socket client' do
      channel.instance_variable_set(:@socket_client, nil)
      expect { channel.stop }.not_to raise_error
    end
  end

  describe '#send' do
    let(:message) do
      Nanobot::Bus::OutboundMessage.new(
        channel: 'slack',
        chat_id: 'C12345',
        content: 'Hello user',
        metadata: {
          'slack' => {
            'thread_ts' => '1234567890.123456',
            'channel_type' => 'channel'
          }
        }
      )
    end

    before do
      allow(web_client).to receive(:chat_postMessage)
    end

    it 'sends message via web client' do
      channel.send(message)

      expect(web_client).to have_received(:chat_postMessage).with(
        channel: 'C12345',
        text: 'Hello user',
        thread_ts: '1234567890.123456'
      )
    end

    it 'replies in thread for group messages' do
      channel.send(message)

      expect(web_client).to have_received(:chat_postMessage).with(
        hash_including(thread_ts: '1234567890.123456')
      )
    end

    it 'does not use thread_ts for DMs' do
      dm_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'slack',
        chat_id: 'D12345',
        content: 'Hello',
        metadata: {
          'slack' => {
            'thread_ts' => '1234567890.123456',
            'channel_type' => 'im'
          }
        }
      )

      channel.send(dm_message)

      expect(web_client).to have_received(:chat_postMessage).with(
        channel: 'D12345',
        text: 'Hello',
        thread_ts: nil
      )
    end

    it 'handles missing slack metadata' do
      plain_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'slack',
        chat_id: 'C12345',
        content: 'Hello'
      )

      channel.send(plain_message)

      expect(web_client).to have_received(:chat_postMessage).with(
        channel: 'C12345',
        text: 'Hello',
        thread_ts: nil
      )
    end

    it 'handles nil content' do
      nil_message = Nanobot::Bus::OutboundMessage.new(
        channel: 'slack',
        chat_id: 'C12345',
        content: nil
      )

      channel.send(nil_message)

      expect(web_client).to have_received(:chat_postMessage).with(
        hash_including(text: '')
      )
    end

    it 'does nothing when web_client is nil' do
      channel.web_client = nil
      expect { channel.send(message) }.not_to raise_error
    end
  end

  describe '#handle_slack_message' do
    before do
      allow(bus).to receive(:publish_inbound)
      allow(web_client).to receive(:reactions_add)
    end

    let(:dm_data) do
      {
        'user' => 'U99999',
        'channel' => 'D12345',
        'text' => 'Hello bot',
        'channel_type' => 'im',
        'ts' => '1234567890.123456'
      }
    end

    let(:group_data) do
      {
        'user' => 'U99999',
        'channel' => 'C12345',
        'text' => '<@U12345> hello bot',
        'channel_type' => 'channel',
        'ts' => '1234567890.123456'
      }
    end

    it 'processes DM messages' do
      channel.handle_slack_message(dm_data)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg).to be_a(Nanobot::Bus::InboundMessage)
        expect(msg.channel).to eq('slack')
        expect(msg.sender_id).to eq('U99999')
        expect(msg.chat_id).to eq('D12345')
        expect(msg.content).to eq('Hello bot')
      end
    end

    it 'processes group messages with bot mention' do
      channel.handle_slack_message(group_data)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg.content).to eq('hello bot')
      end
    end

    it 'adds eyes reaction to messages' do
      channel.handle_slack_message(dm_data)

      expect(web_client).to have_received(:reactions_add).with(
        channel: 'D12345',
        name: 'eyes',
        timestamp: '1234567890.123456'
      )
    end

    it 'passes thread_ts in metadata' do
      channel.handle_slack_message(dm_data)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg.metadata).to eq({
                                     'slack' => {
                                       'thread_ts' => '1234567890.123456',
                                       'channel_type' => 'im'
                                     }
                                   })
      end
    end

    it 'uses thread_ts from data when present' do
      threaded_data = dm_data.merge('thread_ts' => '1234567880.000000')

      channel.handle_slack_message(threaded_data)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg.metadata['slack']['thread_ts']).to eq('1234567880.000000')
      end
    end

    it 'filters messages with subtypes' do
      data = dm_data.merge('subtype' => 'bot_message')
      channel.handle_slack_message(data)
      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'filters self messages from the bot' do
      data = dm_data.merge('user' => 'U12345')
      channel.handle_slack_message(data)
      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'filters messages without sender_id' do
      data = dm_data.merge('user' => nil)
      channel.handle_slack_message(data)
      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'filters messages without chat_id' do
      data = dm_data.merge('channel' => nil)
      channel.handle_slack_message(data)
      expect(bus).not_to have_received(:publish_inbound)
    end

    it 'handles empty text' do
      data = dm_data.merge('text' => nil)
      channel.handle_slack_message(data)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg.content).to eq('')
      end
    end

    it 'ignores group messages without bot mention when policy is mention' do
      data = group_data.merge('text' => 'hello everyone')
      channel.handle_slack_message(data)
      expect(bus).not_to have_received(:publish_inbound)
    end
  end

  describe '#allowed_slack?' do
    context 'with DM messages' do
      it 'allows all DMs when policy is open' do
        expect(channel.allowed_slack?('U99999', 'D12345', 'im')).to be true
      end

      it 'rejects DMs when DM is disabled' do
        disabled_dm = Nanobot::Config::SlackDMConfig.new(enabled: false)
        config_no_dm = double(
          'config',
          dm: disabled_dm,
          group_policy: 'mention',
          group_allow_from: []
        )

        ch = test_channel_class.new(name: 'slack', config: config_no_dm, bus: bus, logger: logger)
        expect(ch.allowed_slack?('U99999', 'D12345', 'im')).to be false
      end

      it 'allows DMs from allowlisted users' do
        allowlist_dm = Nanobot::Config::SlackDMConfig.new(
          enabled: true, policy: 'allowlist', allow_from: ['U99999']
        )
        config_allowlist = double(
          'config',
          dm: allowlist_dm,
          group_policy: 'mention',
          group_allow_from: []
        )

        ch = test_channel_class.new(name: 'slack', config: config_allowlist, bus: bus, logger: logger)
        expect(ch.allowed_slack?('U99999', 'D12345', 'im')).to be true
      end

      it 'rejects DMs from non-allowlisted users' do
        allowlist_dm = Nanobot::Config::SlackDMConfig.new(
          enabled: true, policy: 'allowlist', allow_from: ['U11111']
        )
        config_allowlist = double(
          'config',
          dm: allowlist_dm,
          group_policy: 'mention',
          group_allow_from: []
        )

        ch = test_channel_class.new(name: 'slack', config: config_allowlist, bus: bus, logger: logger)
        expect(ch.allowed_slack?('U99999', 'D12345', 'im')).to be false
      end
    end

    context 'with group messages' do
      it 'allows group messages when policy is not allowlist' do
        expect(channel.allowed_slack?('U99999', 'C12345', 'channel')).to be true
      end

      it 'allows group messages from allowlisted channels' do
        config_allowlist = double(
          'config',
          dm: dm_config,
          group_policy: 'allowlist',
          group_allow_from: ['C12345']
        )

        ch = test_channel_class.new(name: 'slack', config: config_allowlist, bus: bus, logger: logger)
        expect(ch.allowed_slack?('U99999', 'C12345', 'channel')).to be true
      end

      it 'rejects group messages from non-allowlisted channels' do
        config_allowlist = double(
          'config',
          dm: dm_config,
          group_policy: 'allowlist',
          group_allow_from: ['C11111']
        )

        ch = test_channel_class.new(name: 'slack', config: config_allowlist, bus: bus, logger: logger)
        expect(ch.allowed_slack?('U99999', 'C12345', 'channel')).to be false
      end
    end
  end

  describe '#should_respond_in_channel?' do
    it 'responds to all messages when policy is open' do
      open_config = double(
        'config',
        dm: dm_config,
        group_policy: 'open',
        group_allow_from: [],
        bot_token: 'token',
        app_token: 'token'
      )

      ch = test_channel_class.new(name: 'slack', config: open_config, bus: bus, logger: logger)
      expect(ch.should_respond_in_channel?('hello', 'C12345')).to be true
    end

    it 'responds only when mentioned with mention policy' do
      expect(channel.should_respond_in_channel?('<@U12345> hello', 'C12345')).to be true
      expect(channel.should_respond_in_channel?('hello', 'C12345')).to be false
    end

    it 'responds in allowlisted channels with allowlist policy' do
      config_allowlist = double(
        'config',
        dm: dm_config,
        group_policy: 'allowlist',
        group_allow_from: ['C12345']
      )

      ch = test_channel_class.new(name: 'slack', config: config_allowlist, bus: bus, logger: logger)
      ch.bot_user_id = 'U12345'

      expect(ch.should_respond_in_channel?('hello', 'C12345')).to be true
      expect(ch.should_respond_in_channel?('hello', 'C99999')).to be false
    end

    it 'returns false for unknown policy' do
      unknown_config = double(
        'config',
        dm: dm_config,
        group_policy: 'unknown',
        group_allow_from: []
      )

      ch = test_channel_class.new(name: 'slack', config: unknown_config, bus: bus, logger: logger)
      expect(ch.should_respond_in_channel?('hello', 'C12345')).to be false
    end

    it 'returns false for mention policy when bot_user_id is nil' do
      channel.bot_user_id = nil
      expect(channel.should_respond_in_channel?('<@U12345> hello', 'C12345')).to be false
    end
  end

  describe '#strip_bot_mention' do
    it 'strips bot mention from text' do
      expect(channel.strip_bot_mention('<@U12345> hello bot')).to eq('hello bot')
    end

    it 'strips mention with extra whitespace' do
      expect(channel.strip_bot_mention('<@U12345>   hello')).to eq('hello')
    end

    it 'strips mention at end of text' do
      expect(channel.strip_bot_mention('hello <@U12345>')).to eq('hello')
    end

    it 'handles text without mention' do
      expect(channel.strip_bot_mention('hello world')).to eq('hello world')
    end

    it 'returns text unchanged when bot_user_id is nil' do
      channel.bot_user_id = nil
      expect(channel.strip_bot_mention('<@U12345> hello')).to eq('<@U12345> hello')
    end

    it 'handles multiple mentions' do
      expect(channel.strip_bot_mention('<@U12345> hello <@U12345> world')).to eq('hello world')
    end
  end

  describe '#add_eyes_reaction' do
    it 'adds eyes reaction' do
      allow(web_client).to receive(:reactions_add)

      channel.add_eyes_reaction('C12345', '1234567890.123456')

      expect(web_client).to have_received(:reactions_add).with(
        channel: 'C12345',
        name: 'eyes',
        timestamp: '1234567890.123456'
      )
    end

    it 'handles reaction errors gracefully' do
      allow(web_client).to receive(:reactions_add).and_raise(StandardError, 'already_reacted')

      expect { channel.add_eyes_reaction('C12345', '1234567890.123456') }.not_to raise_error
    end

    it 'skips when timestamp is nil' do
      allow(web_client).to receive(:reactions_add)

      channel.add_eyes_reaction('C12345', nil)

      expect(web_client).not_to have_received(:reactions_add)
    end

    it 'skips when web_client is nil' do
      channel.web_client = nil
      expect { channel.add_eyes_reaction('C12345', '1234567890.123456') }.not_to raise_error
    end
  end

  describe '#allowed?' do
    it 'always returns true (Slack uses allowed_slack? instead)' do
      expect(channel.allowed?('anyone')).to be true
    end
  end
end
