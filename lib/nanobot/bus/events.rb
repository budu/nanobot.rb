# frozen_string_literal: true

require 'time'

module Nanobot
  module Bus
    # InboundMessage represents a message coming into the system from a channel
    InboundMessage = Struct.new(
      :channel,
      :sender_id,
      :chat_id,
      :content,
      :timestamp,
      :media,
      :metadata,
      keyword_init: true
    ) do
      def initialize(channel:, sender_id:, chat_id:, content:, **opts)
        super(
          channel: channel,
          sender_id: sender_id,
          chat_id: chat_id,
          content: content,
          timestamp: opts[:timestamp] || Time.now,
          media: opts[:media] || [],
          metadata: opts[:metadata] || {}
        )
      end

      def session_key
        "#{channel}:#{chat_id}"
      end
    end

    # OutboundMessage represents a message going out from the system to a channel
    OutboundMessage = Struct.new(
      :channel,
      :chat_id,
      :content,
      :reply_to,
      :media,
      :metadata,
      keyword_init: true
    ) do
      def initialize(channel:, chat_id:, content:, reply_to: nil, media: nil, metadata: nil)
        super(
          channel: channel,
          chat_id: chat_id,
          content: content,
          reply_to: reply_to,
          media: media || [],
          metadata: metadata || {}
        )
      end
    end
  end
end
