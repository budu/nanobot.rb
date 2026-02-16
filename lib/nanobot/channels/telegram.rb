# frozen_string_literal: true

begin
  require 'telegram/bot'
rescue LoadError
  raise LoadError, 'telegram-bot-ruby gem is required for Telegram channel. Add it to your Gemfile.'
end

module Nanobot
  module Channels
    class Telegram < BaseChannel
      def start
        @running = true
        ::Telegram::Bot::Client.run(@config.token) do |bot|
          @bot = bot
          register_commands(bot)
          bot.listen do |message|
            break unless @running
            next unless message.is_a?(::Telegram::Bot::Types::Message)
            next unless message.text

            start_typing(message.chat.id.to_s)
            handle_message(
              sender_id: message.from.id.to_s,
              chat_id: message.chat.id.to_s,
              content: message.text
            )
          end
        end
      end

      def stop
        @running = false
      end

      def send(message)
        return unless @bot

        stop_typing(message.chat_id)
        split_message(message.content, 4096).each do |chunk|
          @bot.api.send_message(chat_id: message.chat_id, text: chunk)
        end
      end

      private

      def register_commands(bot)
        bot.api.set_my_commands(commands: [
                                  { command: 'new', description: 'Start a new session' },
                                  { command: 'help', description: 'Show help' }
                                ])
      rescue StandardError => e
        @logger.warn "Failed to register Telegram commands: #{e.message}"
      end

      def split_message(text, limit)
        return [''] if text.nil? || text.empty?

        text.chars.each_slice(limit).map(&:join)
      end

      def start_typing(chat_id)
        @typing_threads ||= {}
        @typing_threads[chat_id]&.kill
        @typing_threads[chat_id] = Thread.new do
          loop do
            @bot&.api&.send_chat_action(chat_id: chat_id, action: 'typing')
            sleep 4
          rescue StandardError
            break
          end
        end
      end

      def stop_typing(chat_id)
        @typing_threads&.delete(chat_id)&.kill
      end
    end
  end
end
