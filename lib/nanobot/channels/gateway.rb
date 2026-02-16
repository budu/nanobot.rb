# frozen_string_literal: true

require 'webrick'
require 'json'
require 'securerandom'
require 'timeout'

module Nanobot
  module Channels
    class Gateway < BaseChannel
      def start
        @running = true
        @response_queues = {}
        @queues_mutex = Mutex.new

        @server = WEBrick::HTTPServer.new(
          Port: @config.port,
          BindAddress: @config.host,
          Logger: WEBrick::Log.new(IO::NULL),
          AccessLog: []
        )

        @server.mount_proc('/chat') { |req, res| handle_http_request(req, res) }
        @server.mount_proc('/health') { |_req, res| handle_health(res) }

        @logger.info "Gateway listening on #{@config.host}:#{@config.port}"
        @server.start
      end

      def stop
        @running = false
        @server&.shutdown
      end

      def send(message)
        queue = @queues_mutex.synchronize { @response_queues.delete(message.chat_id) }
        queue&.push(message)
      end

      private

      def handle_http_request(req, res)
        return error_response(res, 405, 'Method not allowed') unless req.request_method == 'POST'

        return error_response(res, 401, 'Unauthorized') unless authorized?(req)

        body = JSON.parse(req.body)
        content = body['message']
        return error_response(res, 400, 'Missing "message" field') unless content

        chat_id = body['chat_id'] || SecureRandom.uuid

        queue = Queue.new
        @queues_mutex.synchronize { @response_queues[chat_id] = queue }

        handle_message(sender_id: 'api', chat_id: chat_id, content: content)

        begin
          response = Timeout.timeout(120) { queue.pop }
          res.content_type = 'application/json'
          res.body = JSON.generate({ chat_id: chat_id, response: response.content })
        rescue Timeout::Error
          @queues_mutex.synchronize { @response_queues.delete(chat_id) }
          error_response(res, 504, 'Gateway timeout')
        end
      rescue JSON::ParserError
        error_response(res, 400, 'Invalid JSON')
      end

      def handle_health(res)
        res.content_type = 'application/json'
        res.body = JSON.generate({ status: 'ok' })
      end

      def authorized?(req)
        return true unless @config.auth_token

        req['Authorization'] == "Bearer #{@config.auth_token}"
      end

      def error_response(res, status, message)
        res.status = status
        res.content_type = 'application/json'
        res.body = JSON.generate({ error: message })
      end
    end
  end
end
