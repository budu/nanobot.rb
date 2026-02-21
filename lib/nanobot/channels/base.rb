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

      # Check if a sender is allowed to use this channel.
      # An empty allow_from list denies all senders (fail-closed).
      # Use ["*"] to explicitly allow all senders.
      # @param sender_id [String] sender identifier
      # @return [Boolean]
      def allowed?(sender_id)
        allow_from = config.allow_from || []

        if allow_from.empty?
          unless @allow_from_warned
            @logger.warn "Channel '#{@name}' has an empty allow_from list - denying all senders. " \
                         'Set allow_from: ["*"] to allow everyone.'
            @allow_from_warned = true
          end
          return false
        end

        return true if allow_from.include?('*')

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
      # @param metadata [Hash] optional channel-specific metadata
      def handle_message(sender_id:, chat_id:, content:, media: [], metadata: {})
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
          media: media,
          metadata: metadata
        )

        # Publish to bus
        @bus.publish_inbound(message)
        @logger.debug "Received message from #{@name}:#{chat_id}"
      end
    end
  end
end
