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
      # @param channel [String] source channel name (e.g. 'telegram', 'slack')
      # @param sender_id [String] unique identifier for the message sender
      # @param chat_id [String] unique identifier for the chat/conversation
      # @param content [String] message text content
      # @param opts [Hash] optional fields: :timestamp, :media, :metadata
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

      # Generates a unique session key combining channel and chat_id
      # @return [String] key in the format "channel:chat_id"
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
      # @param channel [String] target channel name
      # @param chat_id [String] target chat/conversation ID
      # @param content [String] message text content
      # @param reply_to [String, nil] ID of message being replied to
      # @param media [Array, nil] media attachments
      # @param metadata [Hash, nil] additional metadata
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
