# frozen_string_literal: true

begin
  require 'discordrb'
rescue LoadError
  raise LoadError, 'discordrb gem is required for Discord channel. Add it to your Gemfile.'
end

module Nanobot
  module Channels
    class Discord < BaseChannel
      def start
        @running = true
        @bot = Discordrb::Bot.new(token: @config.token, intents: [:server_messages])

        @bot.message do |event|
          next if event.author.bot_account?
          next unless allowed?(event.author.id.to_s)

          handle_message(
            sender_id: event.author.id.to_s,
            chat_id: event.channel.id.to_s,
            content: event.content
          )
        end

        @logger.info 'Discord bot connecting...'
        @bot.run
      end

      def stop
        @running = false
        @bot&.stop
      end

      def send(message)
        return unless @bot

        channel = @bot.channel(message.chat_id.to_i)
        return unless channel

        split_message(message.content, 2000).each do |chunk|
          channel.send_message(chunk)
        end
      end

      private

      def split_message(text, limit)
        return [''] if text.nil? || text.empty?

        text.chars.each_slice(limit).map(&:join)
      end
    end
  end
end
