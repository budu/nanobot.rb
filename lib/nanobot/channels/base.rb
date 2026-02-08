# frozen_string_literal: true

require 'logger'

module Nanobot
  module Channels
    # Base class for all channel implementations
    class BaseChannel
      attr_reader :name, :config, :bus, :logger

      def initialize(name:, config:, bus:, logger: nil)
        @name = name
        @config = config
        @bus = bus
        @logger = logger || Logger.new(IO::NULL)
        @running = false
      end

      # Start the channel (connect and begin listening)
      def start
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      # Stop the channel (disconnect and cleanup)
      def stop
        raise NotImplementedError, "#{self.class} must implement #stop"
      end

      # Send a message through this channel
      # @param message [Bus::OutboundMessage] message to send
      def send(message)
        raise NotImplementedError, "#{self.class} must implement #send"
      end

      # Check if a sender is allowed to use this channel
      # @param sender_id [String] sender identifier
      # @return [Boolean]
      def allowed?(sender_id)
        allow_from = config.allow_from || []

        # Empty list means allow all
        return true if allow_from.empty?

        # Check if sender is in whitelist
        allow_from.include?(sender_id.to_s)
      end

      # Check if channel is running
      # @return [Boolean]
      def running?
        @running
      end

      protected

      # Handle an incoming message (called by subclasses)
      # @param sender_id [String] sender identifier
      # @param chat_id [String] chat identifier
      # @param content [String] message content
      # @param media [Array] optional media attachments
      def handle_message(sender_id:, chat_id:, content:, media: [])
        # Check access control
        unless allowed?(sender_id)
          @logger.warn "Access denied for #{sender_id} on channel #{@name}"
          return
        end

        # Create inbound message
        message = Bus::InboundMessage.new(
          channel: @name,
          sender_id: sender_id,
          chat_id: chat_id,
          content: content,
          media: media
        )

        # Publish to bus
        @bus.publish_inbound(message)
        @logger.debug "Received message from #{@name}:#{chat_id}"
      end
    end
  end
end
