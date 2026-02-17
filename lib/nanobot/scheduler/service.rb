# frozen_string_literal: true

require 'logger'
require_relative '../bus/events'

module Nanobot
  module Scheduler
    # SchedulerService runs a background thread that evaluates schedules
    # and publishes InboundMessages to the bus when jobs are due
    class SchedulerService
      TICK_INTERVAL = 15

      # @param store [ScheduleStore] schedule persistence layer
      # @param bus [Bus::MessageBus] message bus for publishing inbound messages
      # @param logger [Logger, nil] optional logger
      # @param tick_interval [Numeric] seconds between schedule evaluation ticks
      def initialize(store:, bus:, logger: nil, tick_interval: TICK_INTERVAL)
        @store = store
        @bus = bus
        @logger = logger || Logger.new(IO::NULL)
        @tick_interval = tick_interval
        @running = false
        @thread = nil
      end

      def start
        @running = true
        setup_response_routing
        @thread = Thread.new { run_loop }
        @logger.info "Scheduler service started (tick: #{@tick_interval}s)"
      end

      def stop
        @running = false
        @thread&.join(5)
        @logger.info 'Scheduler service stopped'
      end

      def running?
        @running
      end

      private

      def run_loop
        loop do
          break unless @running

          tick
          sleep @tick_interval
        end
      end

      def tick
        now = Time.now
        due = @store.due_schedules(now)
        due.each { |schedule| fire(schedule, now) }
      rescue StandardError => e
        @logger.error "Scheduler tick error: #{e.message}"
      end

      def fire(schedule, now)
        @logger.info "Firing schedule #{schedule.id}: #{schedule.prompt[0..60]}"

        msg = Bus::InboundMessage.new(
          channel: 'scheduler',
          sender_id: 'scheduler',
          chat_id: "schedule:#{schedule.id}",
          content: schedule.prompt,
          metadata: {
            schedule_id: schedule.id,
            deliver_to: schedule.deliver_to
          }
        )

        @bus.publish_inbound(msg)
        @store.advance!(schedule, now)
      rescue StandardError => e
        @logger.error "Error firing schedule #{schedule.id}: #{e.message}"
      end

      def setup_response_routing
        @bus.subscribe_outbound('scheduler') do |outbound_msg|
          route_response(outbound_msg)
        end
      end

      def route_response(outbound_msg)
        schedule_id = outbound_msg.chat_id&.delete_prefix('schedule:')
        schedule = @store.get(schedule_id)
        return unless schedule&.deliver_to

        target_channel = schedule.deliver_to[:channel] || schedule.deliver_to['channel']
        target_chat_id = schedule.deliver_to[:chat_id] || schedule.deliver_to['chat_id']
        return unless target_channel && target_chat_id

        routed = Bus::OutboundMessage.new(
          channel: target_channel,
          chat_id: target_chat_id,
          content: outbound_msg.content
        )
        @bus.publish_outbound(routed)
      rescue StandardError => e
        @logger.error "Error routing scheduled response: #{e.message}"
      end
    end
  end
end
