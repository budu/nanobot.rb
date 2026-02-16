# frozen_string_literal: true

begin
  require 'slack-ruby-client'
rescue LoadError
  raise LoadError, 'slack-ruby-client gem is required for Slack channel. Add it to your Gemfile.'
end

module Nanobot
  module Channels
    # Slack channel integration using Socket Mode via the slack-ruby-client gem.
    # Supports DMs, group mentions, and configurable access control policies.
    class Slack < BaseChannel
      def start
        @running = true
        @bot_user_id = nil

        ::Slack.configure do |c|
          c.token = @config.bot_token
        end

        @web_client = ::Slack::Web::Client.new
        @socket_client = ::Slack::RealTime::Client.new(token: @config.app_token)

        resolve_bot_user_id

        @socket_client.on :message do |data|
          handle_slack_message(data)
        end

        @logger.info 'Slack bot connecting via Socket Mode...'
        @socket_client.start!
      end

      def stop
        @running = false
        @socket_client&.stop!
      end

      # Send a reply via Slack, threading in channels but not in DMs.
      # @param message [Bus::OutboundMessage] message to send
      def send(message)
        return unless @web_client

        slack_meta = message.metadata['slack'] || {}
        thread_ts = slack_meta['thread_ts']
        channel_type = slack_meta['channel_type']
        use_thread = thread_ts && channel_type != 'im'

        @web_client.chat_postMessage(
          channel: message.chat_id,
          text: message.content || '',
          thread_ts: use_thread ? thread_ts : nil
        )
      end

      # Always returns true; Slack uses its own ACL via allowed_slack? instead.
      def allowed?(_sender_id)
        true
      end

      private

      # Fetch the bot's own Slack user ID via auth_test for mention detection.
      def resolve_bot_user_id
        auth = @web_client.auth_test
        @bot_user_id = auth['user_id']
        @logger.info "Slack bot connected as #{@bot_user_id}"
      rescue StandardError => e
        @logger.warn "Slack auth_test failed: #{e.message}"
      end

      # Process an incoming Slack message event, applying access control and
      # bot-mention filtering before dispatching to the message bus.
      # @param data [Hash] Slack event payload
      def handle_slack_message(data)
        return if data['subtype']
        return if @bot_user_id && data['user'] == @bot_user_id

        sender_id = data['user']
        chat_id = data['channel']
        text = data['text'] || ''
        channel_type = data['channel_type'] || ''

        return unless sender_id && chat_id
        return unless allowed_slack?(sender_id, chat_id, channel_type)

        return if (channel_type != 'im') && !should_respond_in_channel?(text, chat_id)

        text = strip_bot_mention(text)
        thread_ts = data['thread_ts'] || data['ts']

        add_eyes_reaction(chat_id, data['ts'])

        handle_message(
          sender_id: sender_id,
          chat_id: chat_id,
          content: text,
          metadata: {
            'slack' => {
              'thread_ts' => thread_ts,
              'channel_type' => channel_type
            }
          }
        )
      end

      # Check Slack-specific access control based on DM/group policies.
      # @param sender_id [String] Slack user ID
      # @param chat_id [String] Slack channel ID
      # @param channel_type [String] "im" for DMs, other for group channels
      # @return [Boolean]
      def allowed_slack?(sender_id, chat_id, channel_type)
        if channel_type == 'im'
          return false unless @config.dm.enabled

          return @config.dm.policy != 'allowlist' || @config.dm.allow_from.include?(sender_id)
        end

        return true unless @config.group_policy == 'allowlist'

        @config.group_allow_from.include?(chat_id)
      end

      # Determine whether the bot should respond in a group channel based on
      # group_policy (open, mention, or allowlist).
      # @param text [String] message text
      # @param chat_id [String] Slack channel ID
      # @return [Boolean]
      def should_respond_in_channel?(text, chat_id)
        case @config.group_policy
        when 'open' then true
        when 'mention'
          !!(@bot_user_id && text.include?("<@#{@bot_user_id}>"))
        when 'allowlist'
          @config.group_allow_from.include?(chat_id)
        else false
        end
      end

      # Remove the bot's @mention from message text.
      # @param text [String] raw message text
      # @return [String] text with bot mention stripped
      def strip_bot_mention(text)
        return text unless @bot_user_id

        text.gsub(/<@#{Regexp.escape(@bot_user_id)}>\s*/, '').strip
      end

      # Add an :eyes: reaction to acknowledge receipt of a message.
      # @param channel [String] Slack channel ID
      # @param timestamp [String] message timestamp for the reaction
      def add_eyes_reaction(channel, timestamp)
        return unless @web_client && timestamp

        @web_client.reactions_add(channel: channel, name: 'eyes', timestamp: timestamp)
      rescue StandardError => e
        @logger.debug "Slack reactions_add failed: #{e.message}"
      end
    end
  end
end
