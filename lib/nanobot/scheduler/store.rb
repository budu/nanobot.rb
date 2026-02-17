# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'
require 'fileutils'
require 'fugit'

module Nanobot
  module Scheduler
    # A single scheduled task
    Schedule = Struct.new(
      :id, :kind, :expression, :timezone, :prompt,
      :deliver_to, :enabled, :created_at, :last_run_at, :next_run_at,
      keyword_init: true
    )

    # ScheduleStore manages schedule CRUD and JSON persistence
    class ScheduleStore
      VALID_KINDS = %w[at every cron].freeze

      attr_reader :path

      # @param path [String, Pathname] path to the schedules JSON file
      def initialize(path: nil)
        @path = Pathname.new(path || File.expand_path('~/.nanobot/schedules.json'))
        @mutex = Mutex.new
        @schedules = {}
        load_from_disk
      end

      # Create a new schedule
      # @param kind [String] "at", "every", or "cron"
      # @param expression [String] time expression (ISO 8601, duration, or cron)
      # @param prompt [String] instruction for the agent
      # @param timezone [String, nil] IANA timezone for cron schedules
      # @param deliver_to [Hash, nil] target channel/chat_id for response routing
      # @return [Schedule]
      def add(kind:, expression:, prompt:, timezone: nil, deliver_to: nil)
        validate_kind!(kind)
        validate_expression!(kind, expression, timezone)

        schedule = Schedule.new(
          id: SecureRandom.uuid,
          kind: kind,
          expression: expression,
          timezone: timezone,
          prompt: prompt,
          deliver_to: deliver_to,
          enabled: true,
          created_at: Time.now.iso8601,
          last_run_at: nil,
          next_run_at: compute_next_run(kind, expression, timezone).iso8601
        )

        @mutex.synchronize do
          @schedules[schedule.id] = schedule
          save_to_disk
        end

        schedule
      end

      # Remove a schedule by ID
      # @param id [String] schedule UUID
      # @return [Boolean] true if removed
      def remove(id)
        @mutex.synchronize do
          removed = @schedules.delete(id)
          save_to_disk if removed
          !removed.nil?
        end
      end

      # Get a schedule by ID
      # @param id [String] schedule UUID
      # @return [Schedule, nil]
      def get(id)
        @mutex.synchronize { @schedules[id] }
      end

      # List all schedules
      # @return [Array<Schedule>]
      def list
        @mutex.synchronize { @schedules.values }
      end

      # Update specific fields on a schedule
      # @param id [String] schedule UUID
      # @param attrs [Hash] fields to update
      # @return [Schedule, nil]
      def update(id, **attrs)
        @mutex.synchronize do
          schedule = @schedules[id]
          return nil unless schedule

          attrs.each { |key, value| schedule[key] = value }
          save_to_disk
          schedule
        end
      end

      # Find schedules that are due for execution
      # @param now [Time] current time
      # @return [Array<Schedule>]
      def due_schedules(now = Time.now)
        @mutex.synchronize do
          @schedules.values.select do |s|
            s.enabled && s.next_run_at && Time.iso8601(s.next_run_at) <= now
          end
        end
      end

      # Advance a schedule after firing
      # @param schedule [Schedule] the schedule that just fired
      # @param now [Time] current time
      def advance!(schedule, now = Time.now)
        @mutex.synchronize do
          s = @schedules[schedule.id]
          return unless s

          s.last_run_at = now.iso8601

          case s.kind
          when 'at'
            s.enabled = false
            s.next_run_at = nil
          when 'every'
            duration = Fugit::Duration.parse(s.expression)
            s.next_run_at = (now + duration.to_sec).iso8601
          when 'cron'
            cron = Fugit::Cron.parse(s.expression)
            s.next_run_at = cron.next_time(now).to_t.iso8601
          end

          save_to_disk
        end
      end

      private

      def validate_kind!(kind)
        return if VALID_KINDS.include?(kind)

        raise ArgumentError, "Invalid schedule kind '#{kind}'. Must be one of: #{VALID_KINDS.join(', ')}"
      end

      def validate_expression!(kind, expression, timezone)
        case kind
        when 'at'
          Time.iso8601(expression)
        when 'every'
          result = Fugit::Duration.parse(expression)
          raise ArgumentError, "Invalid duration expression '#{expression}'" unless result
        when 'cron'
          result = Fugit::Cron.parse(expression)
          raise ArgumentError, "Invalid cron expression '#{expression}'" unless result

          if timezone
            tz = TZInfo::Timezone.get(timezone)
            raise ArgumentError, "Invalid timezone '#{timezone}'" unless tz
          end
        end
      rescue ArgumentError
        raise
      rescue StandardError => e
        raise ArgumentError, "Invalid expression '#{expression}' for kind '#{kind}': #{e.message}"
      end

      def compute_next_run(kind, expression, timezone, from = Time.now)
        case kind
        when 'at'
          Time.iso8601(expression)
        when 'every'
          duration = Fugit::Duration.parse(expression)
          from + duration.to_sec
        when 'cron'
          cron = if timezone
                   Fugit::Cron.parse("#{expression} #{timezone}")
                 else
                   Fugit::Cron.parse(expression)
                 end
          cron.next_time(from).to_t
        end
      end

      def load_from_disk
        return unless @path.exist?

        data = JSON.parse(@path.read, symbolize_names: true)
        return unless data[:schedules].is_a?(Array)

        data[:schedules].each do |attrs|
          schedule = Schedule.new(**attrs)
          @schedules[schedule.id] = schedule
        end
      rescue StandardError
        # If file is corrupted, start fresh
        @schedules = {}
      end

      def save_to_disk
        @path.dirname.mkpath unless @path.dirname.exist?

        data = {
          version: 1,
          schedules: @schedules.values.map { |s| schedule_to_hash(s) }
        }

        # Atomic write: write to temp file then rename
        tmp = Pathname.new("#{@path}.tmp")
        tmp.write(JSON.pretty_generate(data))
        tmp.rename(@path)
        FileUtils.chmod(0o600, @path)
      end

      def schedule_to_hash(schedule)
        {
          id: schedule.id,
          kind: schedule.kind,
          expression: schedule.expression,
          timezone: schedule.timezone,
          prompt: schedule.prompt,
          deliver_to: schedule.deliver_to,
          enabled: schedule.enabled,
          created_at: schedule.created_at,
          last_run_at: schedule.last_run_at,
          next_run_at: schedule.next_run_at
        }
      end
    end
  end
end
