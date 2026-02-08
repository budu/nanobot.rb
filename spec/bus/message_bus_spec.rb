# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Bus::MessageBus do
  let(:bus) { described_class.new(logger: test_logger) }

  describe '#publish_inbound and #consume_inbound' do
    it 'publishes and consumes inbound messages' do
      message = Nanobot::Bus::InboundMessage.new(
        channel: 'test',
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Hello'
      )

      bus.publish_inbound(message)

      consumed = bus.consume_inbound(timeout: 1)
      expect(consumed).to eq(message)
      expect(consumed.session_key).to eq('test:chat1')
    end

    it 'returns nil when timeout expires with no messages' do
      result = bus.consume_inbound(timeout: 0.1)
      expect(result).to be_nil
    end
  end

  describe '#publish_outbound and subscribers' do
    it 'dispatches outbound messages to subscribers' do
      received = []

      bus.subscribe_outbound('test') do |msg|
        received << msg
      end

      bus.start_dispatch

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'test',
        chat_id: 'chat1',
        content: 'Response'
      )

      bus.publish_outbound(message)

      sleep 0.1 # Give dispatcher time to process

      expect(received.length).to eq(1)
      expect(received.first.content).to eq('Response')

      bus.stop
    end
  end

  describe '#queue_sizes' do
    it 'reports queue sizes' do
      message = Nanobot::Bus::InboundMessage.new(
        channel: 'test',
        sender_id: 'user1',
        chat_id: 'chat1',
        content: 'Hello'
      )

      bus.publish_inbound(message)

      sizes = bus.queue_sizes
      expect(sizes[:inbound]).to eq(1)
      expect(sizes[:outbound]).to eq(0)
    end
  end
end
