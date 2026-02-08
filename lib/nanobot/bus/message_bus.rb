# frozen_string_literal: true

require 'logger'
require_relative 'events'

module Nanobot
  module Bus
    # MessageBus provides a thread-safe queue-based message routing system
    # that decouples channels from the agent core
    class MessageBus
      attr_reader :logger

      def initialize(logger: nil)
        @inbound_queue = Queue.new
        @outbound_queue = Queue.new
        @outbound_subscribers = Hash.new { |h, k| h[k] = [] }
        @running = false
        @logger = logger || Logger.new(IO::NULL)
        @dispatch_thread = nil
        @mutex = Mutex.new
      end

      # Publish an inbound message (from channel to agent)
      def publish_inbound(message)
        raise ArgumentError, 'Message must be an InboundMessage' unless message.is_a?(InboundMessage)

        @inbound_queue.push(message)
        @logger.debug "Published inbound message from #{message.channel}:#{message.chat_id}"
      end

      # Consume an inbound message (agent reads from channels)
      # @param timeout [Numeric, nil] timeout in seconds, nil for blocking
      # @return [InboundMessage, nil]
      def consume_inbound(timeout: nil)
        if timeout
          begin
            Timeout.timeout(timeout) do
              @inbound_queue.pop
            end
          rescue Timeout::Error
            nil
          end
        else
          @inbound_queue.pop
        end
      end

      # Publish an outbound message (from agent to channels)
      def publish_outbound(message)
        raise ArgumentError, 'Message must be an OutboundMessage' unless message.is_a?(OutboundMessage)

        @outbound_queue.push(message)
        @logger.debug "Published outbound message to #{message.channel}:#{message.chat_id}"
      end

      # Subscribe to outbound messages for a specific channel
      # @param channel [String] channel name
      # @param callback [Proc] callback to invoke with OutboundMessage
      def subscribe_outbound(channel, &callback)
        raise ArgumentError, 'Block required' unless block_given?

        @mutex.synchronize do
          @outbound_subscribers[channel] << callback
        end
        @logger.debug "Subscribed to outbound messages for channel: #{channel}"
      end

      # Start the outbound dispatcher thread
      def start_dispatch
        @mutex.synchronize do
          return if @running

          @running = true
        end
        @dispatch_thread = Thread.new do
          dispatch_loop
        end
        @logger.info 'Message bus dispatch started'
      end

      # Stop the message bus
      def stop
        @running = false
        @outbound_queue.push(nil) # Unblock the dispatch thread
        @dispatch_thread&.join(5) # Wait up to 5 seconds
        @logger.info 'Message bus stopped'
      end

      # Check if the message bus is running
      def running?
        @running
      end

      # Get queue sizes for monitoring
      def queue_sizes
        {
          inbound: @inbound_queue.size,
          outbound: @outbound_queue.size
        }
      end

      private

      # Main dispatch loop that routes outbound messages to subscribers
      def dispatch_loop
        loop do
          break unless @running

          message = @outbound_queue.pop
          break unless message # nil is stop signal

          dispatch_message(message)
        end
      rescue StandardError => e
        @logger.error "Error in dispatch loop: #{e.message}"
        @logger.error e.backtrace.join("\n")
        @running = false
      end

      # Dispatch a single message to all subscribers for its channel
      def dispatch_message(message)
        subscribers = @mutex.synchronize { @outbound_subscribers[message.channel].dup }

        if subscribers.empty?
          @logger.warn "No subscribers for channel: #{message.channel}"
          return
        end

        subscribers.each do |callback|
          dispatch_to_subscriber(callback, message)
        end
      end

      # Dispatch to a single subscriber with error handling
      def dispatch_to_subscriber(callback, message)
        callback.call(message)
      rescue StandardError => e
        @logger.error "Error dispatching to #{message.channel}: #{e.message}"
        @logger.error e.backtrace.join("\n")
      end
    end
  end
end
