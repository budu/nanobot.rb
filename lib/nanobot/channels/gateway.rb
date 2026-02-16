# frozen_string_literal: true

require 'webrick'
require 'json'
require 'securerandom'
require 'timeout'

module Nanobot
  module Channels
    # HTTP Gateway channel exposing a synchronous /chat REST endpoint via WEBrick.
    # Supports optional Bearer token authentication and a /health endpoint.
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

      # Deliver a response to the waiting HTTP request by pushing onto its queue.
      # @param message [Bus::OutboundMessage] message to send
      def send(message)
        queue = @queues_mutex.synchronize { @response_queues.delete(message.chat_id) }
        queue&.push(message)
      end

      private

      # Handle a POST /chat request: parse JSON body, dispatch to the bus, and
      # block until a response arrives or timeout (120s).
      # @param req [WEBrick::HTTPRequest]
      # @param res [WEBrick::HTTPResponse]
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

      # Respond with a JSON health check status.
      # @param res [WEBrick::HTTPResponse]
      def handle_health(res)
        res.content_type = 'application/json'
        res.body = JSON.generate({ status: 'ok' })
      end

      # Check Bearer token authorization if auth_token is configured.
      # @param req [WEBrick::HTTPRequest]
      # @return [Boolean]
      def authorized?(req)
        return true unless @config.auth_token

        req['Authorization'] == "Bearer #{@config.auth_token}"
      end

      # Write a JSON error response.
      # @param res [WEBrick::HTTPResponse]
      # @param status [Integer] HTTP status code
      # @param message [String] error message
      def error_response(res, status, message)
        res.status = status
        res.content_type = 'application/json'
        res.body = JSON.generate({ error: message })
      end
    end
  end
end
