# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Channel integration' do # rubocop:disable RSpec/DescribeClass
  let(:bus) { Nanobot::Bus::MessageBus.new(logger: test_logger) }
  let(:logger) { test_logger }

  describe 'full message round-trip' do
    it 'routes inbound message through bus to outbound subscriber' do
      received = []

      bus.subscribe_outbound('test_channel') do |msg|
        received << msg
      end

      bus.start_dispatch

      # Simulate channel publishing an inbound message
      inbound = Nanobot::Bus::InboundMessage.new(
        channel: 'test_channel',
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Hello'
      )
      bus.publish_inbound(inbound)

      # Simulate agent consuming and producing outbound
      consumed = bus.consume_inbound(timeout: 2)
      expect(consumed).not_to be_nil
      expect(consumed.content).to eq('Hello')
      expect(consumed.session_key).to eq('test_channel:chat1')

      outbound = Nanobot::Bus::OutboundMessage.new(
        channel: 'test_channel',
        chat_id: 'chat1',
        content: 'Response'
      )
      bus.publish_outbound(outbound)

      sleep 0.2 # Allow dispatch

      expect(received.length).to eq(1)
      expect(received.first.content).to eq('Response')
      expect(received.first.chat_id).to eq('chat1')

      bus.stop
    end
  end

  describe 'multi-channel isolation' do
    it 'routes messages to correct channel subscribers' do
      channel_a_received = []
      channel_b_received = []

      bus.subscribe_outbound('channel_a') { |msg| channel_a_received << msg }
      bus.subscribe_outbound('channel_b') { |msg| channel_b_received << msg }

      bus.start_dispatch

      # Send to channel_a
      bus.publish_outbound(Nanobot::Bus::OutboundMessage.new(
                             channel: 'channel_a', chat_id: 'chat1', content: 'For A'
                           ))

      # Send to channel_b
      bus.publish_outbound(Nanobot::Bus::OutboundMessage.new(
                             channel: 'channel_b', chat_id: 'chat2', content: 'For B'
                           ))

      sleep 0.2

      expect(channel_a_received.length).to eq(1)
      expect(channel_a_received.first.content).to eq('For A')

      expect(channel_b_received.length).to eq(1)
      expect(channel_b_received.first.content).to eq('For B')

      bus.stop
    end
  end

  describe 'session isolation across channels' do
    it 'creates separate session keys for different channels' do
      msg_a = Nanobot::Bus::InboundMessage.new(
        channel: 'telegram', sender_id: 'user1', chat_id: 'chat1', content: 'Hello'
      )
      msg_b = Nanobot::Bus::InboundMessage.new(
        channel: 'discord', sender_id: 'user1', chat_id: 'chat1', content: 'Hello'
      )

      expect(msg_a.session_key).to eq('telegram:chat1')
      expect(msg_b.session_key).to eq('discord:chat1')
      expect(msg_a.session_key).not_to eq(msg_b.session_key)
    end
  end

  describe 'metadata passthrough' do
    it 'preserves metadata through inbound/outbound messages' do
      inbound = Nanobot::Bus::InboundMessage.new(
        channel: 'slack',
        sender_id: 'user1',
        chat_id: 'C123',
        content: 'Hello',
        metadata: { 'slack' => { 'thread_ts' => '1234.5678', 'channel_type' => 'channel' } }
      )

      expect(inbound.metadata['slack']['thread_ts']).to eq('1234.5678')

      outbound = Nanobot::Bus::OutboundMessage.new(
        channel: 'slack',
        chat_id: 'C123',
        content: 'Response',
        metadata: inbound.metadata
      )

      expect(outbound.metadata['slack']['thread_ts']).to eq('1234.5678')
    end
  end

  describe 'channel manager with concrete channel' do
    it 'manages channel lifecycle' do # rubocop:disable RSpec/ExampleLength
      test_channel_class = Class.new(Nanobot::Channels::BaseChannel) do
        attr_reader :started, :stopped, :sent_messages

        def start
          @running = true
          @started = true
          # Simulate a long-running channel
          sleep 0.1 while @running
        end

        def stop
          @running = false
          @stopped = true
        end

        def send(message)
          @sent_messages ||= []
          @sent_messages << message
        end
      end

      config = Nanobot::Config::Config.new
      channel = test_channel_class.new(
        name: 'test_channel',
        config: double('config', allow_from: []),
        bus: bus,
        logger: logger
      )

      manager = Nanobot::Channels::Manager.new(config: config, bus: bus, logger: logger)
      manager.add_channel(channel)

      expect(manager.size).to eq(1)
      expect(manager.channel?('test_channel')).to be true

      manager.start_all
      sleep 0.3 # Allow channel to start

      expect(channel.started).to be true

      # Send outbound message
      bus.publish_outbound(Nanobot::Bus::OutboundMessage.new(
                             channel: 'test_channel', chat_id: 'chat1', content: 'Test response'
                           ))

      sleep 0.2

      expect(channel.sent_messages&.length).to eq(1)
      expect(channel.sent_messages&.first&.content).to eq('Test response')

      manager.stop_all

      expect(channel.stopped).to be true
    end
  end

  describe 'channel config structs' do
    it 'creates config with all channel types' do # rubocop:disable RSpec/MultipleExpectations
      config = Nanobot::Config::Config.new(
        channels: {
          telegram: { enabled: true, token: 'test-token', allow_from: ['123'] },
          discord: { enabled: true, token: 'discord-token' },
          gateway: { enabled: true, port: 9090, auth_token: 'secret' },
          slack: {
            enabled: true, bot_token: 'xoxb-test', app_token: 'xapp-test',
            group_policy: 'mention', dm: { enabled: true, policy: 'open' }
          },
          email: {
            enabled: true, consent_granted: true,
            imap_host: 'imap.test.com', smtp_host: 'smtp.test.com'
          }
        }
      )

      expect(config.channels.telegram.enabled).to be true
      expect(config.channels.telegram.token).to eq('test-token')
      expect(config.channels.telegram.allow_from).to eq(['123'])

      expect(config.channels.discord.enabled).to be true
      expect(config.channels.discord.token).to eq('discord-token')

      expect(config.channels.gateway.enabled).to be true
      expect(config.channels.gateway.port).to eq(9090)
      expect(config.channels.gateway.auth_token).to eq('secret')

      expect(config.channels.slack.enabled).to be true
      expect(config.channels.slack.bot_token).to eq('xoxb-test')
      expect(config.channels.slack.group_policy).to eq('mention')
      expect(config.channels.slack.dm.enabled).to be true
      expect(config.channels.slack.dm.policy).to eq('open')

      expect(config.channels.email.enabled).to be true
      expect(config.channels.email.consent_granted).to be true
    end

    it 'creates config with default disabled channels' do
      config = Nanobot::Config::Config.new

      expect(config.channels.telegram.enabled).to be false
      expect(config.channels.discord.enabled).to be false
      expect(config.channels.gateway.enabled).to be false
      expect(config.channels.slack.enabled).to be false
      expect(config.channels.email.enabled).to be false
    end
  end

  describe 'dispatch loop resilience' do
    it 'continues dispatching after subscriber error' do
      received = []

      bus.subscribe_outbound('test') do |msg|
        raise 'subscriber error' if msg.content == 'bad'

        received << msg
      end

      bus.start_dispatch

      bus.publish_outbound(
        Nanobot::Bus::OutboundMessage.new(channel: 'test', chat_id: '1', content: 'bad')
      )
      bus.publish_outbound(
        Nanobot::Bus::OutboundMessage.new(channel: 'test', chat_id: '1', content: 'good')
      )

      sleep 0.2

      expect(received.length).to eq(1)
      expect(received.first.content).to eq('good')

      bus.stop
    end
  end
end
