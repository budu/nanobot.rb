# frozen_string_literal: true

require 'logger'
require_relative 'base'

module Nanobot
  module Channels
    # ChannelManager orchestrates all channels
    class Manager
      attr_reader :channels, :bus, :logger

      def initialize(config:, bus:, logger: nil)
        @config = config
        @bus = bus
        @logger = logger || Logger.new(IO::NULL)
        @channels = {}
        @threads = []
      end

      # Add a channel
      # @param channel [BaseChannel] channel to add
      def add_channel(channel)
        @channels[channel.name] = channel
        @logger.info "Added channel: #{channel.name}"
      end

      # Start all enabled channels
      def start_all
        @channels.each do |name, channel|
          # Subscribe to outbound messages for this channel
          @bus.subscribe_outbound(name) do |message|
            channel.send(message)
          rescue StandardError => e
            @logger.error "Error sending message on #{name}: #{e.message}"
          end

          # Start channel in separate thread
          thread = Thread.new do
            @logger.info "Starting channel: #{name}"
            channel.start
          rescue StandardError => e
            @logger.error "Error in channel #{name}: #{e.message}"
            @logger.error e.backtrace.join("\n")
          end

          @threads << thread
        end

        # Start bus dispatcher
        @bus.start_dispatch

        @logger.info 'All channels started'
      end

      # Stop all channels
      def stop_all
        @logger.info 'Stopping all channels'

        @channels.each do |name, channel|
          channel.stop
        rescue StandardError => e
          @logger.error "Error stopping #{name}: #{e.message}"
        end

        # Stop bus
        @bus.stop

        # Wait for threads to finish
        @threads.each do |thread|
          thread.join(5) # Wait up to 5 seconds
        end

        @logger.info 'All channels stopped'
      end

      # Get a channel by name
      # @param name [String] channel name
      # @return [BaseChannel, nil]
      def get_channel(name)
        @channels[name]
      end

      # Check if a channel exists
      # @param name [String] channel name
      # @return [Boolean]
      def channel?(name)
        @channels.key?(name)
      end

      # Get count of channels
      # @return [Integer]
      def size
        @channels.size
      end
    end
  end
end
