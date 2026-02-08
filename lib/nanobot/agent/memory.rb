# frozen_string_literal: true

require 'fileutils'

module Nanobot
  module Agent
    # MemoryStore manages persistent memory for the agent
    # Supports both long-term memory and daily notes
    class MemoryStore
      attr_reader :workspace

      def initialize(workspace)
        @workspace = Pathname.new(workspace).expand_path
        @memory_dir = @workspace / 'memory'
        @memory_dir.mkpath unless @memory_dir.exist?
      end

      # Read long-term memory
      # @return [String, nil] content of MEMORY.md or nil if not exists
      def read_long_term
        memory_file = @memory_dir / 'MEMORY.md'
        return nil unless memory_file.exist?

        memory_file.read
      end

      # Write to long-term memory
      # @param content [String] content to write
      def write_long_term(content)
        memory_file = @memory_dir / 'MEMORY.md'
        memory_file.write(content)
      end

      # Append to long-term memory
      # @param content [String] content to append
      def append_long_term(content)
        memory_file = @memory_dir / 'MEMORY.md'
        current = memory_file.exist? ? memory_file.read : ''

        # Add separator if there's existing content
        separator = current.empty? ? '' : "\n\n"
        memory_file.write(current + separator + content)
      end

      # Read today's daily note
      # @return [String, nil] content of today's note or nil if not exists
      def read_today
        file = today_file
        return nil unless file.exist?

        file.read
      end

      # Write to today's daily note
      # @param content [String] content to write
      def write_today(content)
        file = today_file
        file.write(content)
      end

      # Append to today's daily note
      # @param content [String] content to append
      # @param timestamp [Boolean] whether to add timestamp (default: true)
      def append_today(content, timestamp: true)
        file = today_file
        current = file.exist? ? file.read : "# Daily Notes - #{Date.today}\n\n"

        entry = if timestamp
                  "\n## #{Time.now.strftime('%H:%M:%S')}\n\n#{content}"
                else
                  "\n#{content}"
                end

        today_file.write(current + entry)
      end

      # Get memory context for agent prompts
      # @param include_today [Boolean] whether to include today's notes
      # @return [String] formatted memory context
      def get_memory_context(include_today: true)
        parts = []

        # Long-term memory
        long_term = read_long_term
        parts << "## Long-term Memory\n\n#{long_term}" if long_term && !long_term.strip.empty?

        # Today's notes
        if include_today
          today = read_today
          parts << "## Today's Notes\n\n#{today}" if today && !today.strip.empty?
        end

        return nil if parts.empty?

        parts.join("\n\n---\n\n")
      end

      # List all daily notes
      # @return [Array<Hash>] array of {date: Date, path: Pathname}
      def list_daily_notes
        notes = @memory_dir.glob('????-??-??.md').map do |path|
          date_str = path.basename('.md').to_s
          {
            date: Date.parse(date_str),
            path: path
          }
        end
        notes.sort_by { |n| n[:date] }.reverse
      end

      # Read a specific daily note
      # @param date [Date, String] the date to read
      # @return [String, nil]
      def read_daily_note(date)
        date_obj = date.is_a?(Date) ? date : Date.parse(date.to_s)
        note_file = @memory_dir / "#{date_obj.strftime('%Y-%m-%d')}.md"

        return nil unless note_file.exist?

        note_file.read
      end

      private

      def today_file
        @memory_dir / "#{Date.today.strftime('%Y-%m-%d')}.md"
      end
    end
  end
end
