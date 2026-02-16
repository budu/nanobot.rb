# frozen_string_literal: true

require 'logger'
require_relative 'base'

module Nanobot
  module Channels
    # ChannelManager orchestrates all channels
    class Manager
      attr_reader :channels, :bus, :logger

      def initialize(config:, bus:, logger: nil, restart_delay: 5)
        @config = config
        @bus = bus
        @logger = logger || Logger.new(IO::NULL)
        @channels = {}
        @threads = []
        @restart_delay = restart_delay
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

          # Start channel in separate thread with supervision
          thread = start_channel_with_supervision(name, channel, restart_delay: @restart_delay)

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

      private

      def start_channel_with_supervision(name, channel, max_restarts: 3, restart_delay: 5)
        Thread.new do
          restarts = 0
          loop do
            @logger.info "Starting channel: #{name}"
            channel.start
            break # clean exit
          rescue StandardError => e
            restarts += 1
            if restarts <= max_restarts
              delay = restart_delay * restarts
              @logger.warn "Channel #{name} crashed (#{restarts}/#{max_restarts}), " \
                           "restarting in #{delay}s: #{e.message}"
              sleep delay
            else
              @logger.error "Channel #{name} exceeded max restarts, giving up: #{e.message}"
              @logger.error e.backtrace&.join("\n")
              break
            end
          end
        end
      end
    end
  end
end
