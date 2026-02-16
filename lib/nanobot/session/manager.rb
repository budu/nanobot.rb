# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require 'uri'

module Nanobot
  module Session
    # Session represents a conversation session
    class Session
      attr_accessor :key, :messages, :created_at, :updated_at, :metadata

      def initialize(key, messages: [], created_at: nil, updated_at: nil, metadata: {})
        @key = key
        @messages = messages
        @created_at = created_at || Time.now
        @updated_at = updated_at || Time.now
        @metadata = metadata
      end

      # Add a message to the session
      # @param role [String] message role (user, assistant, system, tool)
      # @param content [String] message content
      # @param tool_calls [Array, nil] tool calls (for assistant messages)
      def add_message(role, content, tool_calls: nil)
        message = {
          role: role,
          content: content,
          timestamp: Time.now.iso8601
        }

        message[:tool_calls] = tool_calls if tool_calls

        @messages << message
        @updated_at = Time.now
      end

      # Get recent message history in LLM format
      # @param max_messages [Integer] maximum number of messages to return
      # @return [Array<Hash>] messages in OpenAI format
      def get_history(max_messages: 50)
        recent = if @messages.length > max_messages
                   @messages[-max_messages..]
                 else
                   @messages
                 end

        recent.map do |msg|
          # Return only role and content for LLM
          hash = { role: msg[:role], content: msg[:content] }
          hash[:tool_calls] = msg[:tool_calls] if msg[:tool_calls]
          hash
        end
      end

      # Clear all messages
      def clear
        @messages = []
        @updated_at = Time.now
      end

      # Get message count
      def message_count
        @messages.length
      end
    end

    # SessionManager manages conversation sessions with JSONL persistence
    class Manager
      attr_reader :workspace, :sessions_dir

      def initialize(workspace)
        @workspace = Pathname.new(workspace).expand_path
        @sessions_dir = Pathname.new(File.expand_path('~/.nanobot/sessions'))
        @sessions_dir.mkpath unless @sessions_dir.exist?
        FileUtils.chmod(0o700, @sessions_dir) if @sessions_dir.exist?
        @cache = {}
      end

      # Get or create a session by key
      # @param key [String] session key (format: "channel:chat_id")
      # @return [Session]
      def get_or_create(key)
        return @cache[key] if @cache[key]

        session = load(key) || Session.new(key)
        @cache[key] = session
        session
      end

      # Save a session to disk
      # @param session [Session] session to save
      def save(session)
        path = @sessions_dir / "#{safe_filename(session.key)}.jsonl"

        File.open(path, 'w') do |f|
          # Write metadata line
          metadata_line = {
            _type: 'metadata',
            key: session.key,
            created_at: session.created_at.iso8601,
            updated_at: session.updated_at.iso8601,
            metadata: session.metadata
          }
          f.puts(JSON.generate(metadata_line))

          # Write message lines
          session.messages.each do |msg|
            f.puts(JSON.generate(msg))
          end
        end

        FileUtils.chmod(0o600, path)

        @cache[session.key] = session
      end

      # Delete a session
      # @param key [String] session key
      # @return [Boolean] true if deleted
      def delete(key)
        @cache.delete(key)
        path = @sessions_dir / "#{safe_filename(key)}.jsonl"

        if path.exist?
          path.delete
          true
        else
          false
        end
      end

      # List all sessions
      # @return [Array<Hash>] array of session info
      def list_sessions
        sessions = []

        @sessions_dir.glob('*.jsonl').each do |path|
          first_line = path.readlines.first
          next unless first_line

          data = JSON.parse(first_line, symbolize_names: true)
          next unless data[:_type] == 'metadata'

          # Prefer the key stored in metadata; fall back to decoding the filename
          key = data[:key] || URI.decode_www_form_component(path.basename('.jsonl').to_s)

          sessions << {
            key: key,
            created_at: data[:created_at],
            updated_at: data[:updated_at],
            path: path.to_s
          }
        end

        sessions.sort_by { |s| s[:updated_at] }.reverse
      end

      # Clear all cached sessions
      def clear_cache
        @cache.clear
      end

      # Get number of cached sessions
      def cache_size
        @cache.size
      end

      private

      # Load a session from disk
      # @param key [String] session key
      # @return [Session, nil]
      def load(key)
        path = @sessions_dir / "#{safe_filename(key)}.jsonl"
        return nil unless path.exist?

        messages = []
        metadata = {}
        created_at = nil
        updated_at = nil

        path.each_line do |line|
          next if line.strip.empty?

          data = JSON.parse(line, symbolize_names: true)

          if data[:_type] == 'metadata'
            metadata = data[:metadata] || {}
            created_at = Time.iso8601(data[:created_at]) if data[:created_at]
            updated_at = Time.iso8601(data[:updated_at]) if data[:updated_at]
          else
            messages << data
          end
        end

        Session.new(
          key,
          messages: messages,
          created_at: created_at,
          updated_at: updated_at,
          metadata: metadata
        )
      rescue StandardError
        # If there's an error loading, return nil
        nil
      end

      # Convert session key to safe filename using percent-encoding.
      # This is reversible via URI.decode_www_form_component.
      # @param str [String] session key
      # @return [String] safe filename
      def safe_filename(str)
        URI.encode_www_form_component(str)
      end
    end
  end
end
