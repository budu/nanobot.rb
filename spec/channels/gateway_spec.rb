# frozen_string_literal: true

require 'spec_helper'
require 'nanobot/channels/gateway'

RSpec.describe Nanobot::Channels::Gateway do
  let(:config) { double('config', allow_from: [], port: 0, host: '127.0.0.1', auth_token: nil) }
  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }

  let(:channel) do
    described_class.new(
      name: 'gateway',
      config: config,
      bus: bus,
      logger: logger
    )
  end

  # Expose private methods for unit testing
  let(:test_channel_class) do
    Class.new(described_class) do
      public :handle_http_request, :handle_health, :authorized?, :error_response
    end
  end

  let(:test_channel) do
    inst = test_channel_class.new(name: 'gateway', config: config, bus: bus, logger: logger)
    inst.instance_variable_set(:@running, true)
    inst.instance_variable_set(:@response_queues, {})
    inst.instance_variable_set(:@queues_mutex, Mutex.new)
    inst
  end

  let(:response) { double('response').as_null_object }

  describe '#initialize' do
    it 'inherits from BaseChannel' do
      expect(channel).to be_a(Nanobot::Channels::BaseChannel)
    end

    it 'sets channel attributes' do
      expect(channel.name).to eq('gateway')
      expect(channel.config).to eq(config)
      expect(channel.bus).to eq(bus)
    end
  end

  describe '#start' do
    it 'creates and starts a WEBrick server' do
      server = instance_double(WEBrick::HTTPServer)
      allow(WEBrick::HTTPServer).to receive(:new).and_return(server)
      allow(server).to receive(:mount_proc)
      allow(server).to receive(:start)

      channel.start

      expect(WEBrick::HTTPServer).to have_received(:new).with(
        hash_including(Port: 0, BindAddress: '127.0.0.1')
      )
      expect(server).to have_received(:mount_proc).with('/chat')
      expect(server).to have_received(:mount_proc).with('/health')
      expect(server).to have_received(:start)
    end

    it 'sets running state' do
      server = instance_double(WEBrick::HTTPServer)
      allow(WEBrick::HTTPServer).to receive(:new).and_return(server)
      allow(server).to receive(:mount_proc)
      allow(server).to receive(:start)

      channel.start

      expect(channel.running?).to be true
    end
  end

  describe '#stop' do
    it 'shuts down the server' do
      server = instance_double(WEBrick::HTTPServer)
      channel.instance_variable_set(:@server, server)
      allow(server).to receive(:shutdown)

      channel.stop

      expect(channel.running?).to be false
      expect(server).to have_received(:shutdown)
    end

    it 'handles nil server gracefully' do
      expect { channel.stop }.not_to raise_error
    end
  end

  describe '#send' do
    before do
      channel.instance_variable_set(:@response_queues, {})
      channel.instance_variable_set(:@queues_mutex, Mutex.new)
    end

    it 'routes response to the correct queue' do
      queue = Queue.new
      channel.instance_variable_get(:@response_queues)['chat-123'] = queue

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'gateway',
        chat_id: 'chat-123',
        content: 'Hello back'
      )

      channel.send(message)

      result = queue.pop(true)
      expect(result).to eq(message)
    end

    it 'removes the queue after sending' do
      queue = Queue.new
      channel.instance_variable_get(:@response_queues)['chat-123'] = queue

      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'gateway',
        chat_id: 'chat-123',
        content: 'Hello back'
      )

      channel.send(message)

      expect(channel.instance_variable_get(:@response_queues)).not_to have_key('chat-123')
    end

    it 'handles missing queue gracefully' do
      message = Nanobot::Bus::OutboundMessage.new(
        channel: 'gateway',
        chat_id: 'nonexistent',
        content: 'Hello'
      )

      expect { channel.send(message) }.not_to raise_error
    end
  end

  describe 'private #handle_http_request' do
    let(:request) do
      double('request',
             request_method: 'POST',
             body: '{"message":"hello"}',
             :[] => nil)
    end

    it 'publishes inbound message to bus for valid POST' do
      allow(bus).to receive(:publish_inbound)

      # Simulate response arriving in a thread
      Thread.new do
        sleep 0.05
        queues = test_channel.instance_variable_get(:@response_queues)
        chat_id = queues.keys.first
        next unless chat_id

        queues[chat_id]&.push(
          Nanobot::Bus::OutboundMessage.new(channel: 'gateway', chat_id: chat_id, content: 'response')
        )
      end

      test_channel.handle_http_request(request, response)

      expect(bus).to have_received(:publish_inbound) do |msg|
        expect(msg).to be_a(Nanobot::Bus::InboundMessage)
        expect(msg.channel).to eq('gateway')
        expect(msg.sender_id).to eq('api')
        expect(msg.content).to eq('hello')
      end
    end

    it 'returns JSON response with chat_id' do
      allow(bus).to receive(:publish_inbound)

      Thread.new do
        sleep 0.05
        queues = test_channel.instance_variable_get(:@response_queues)
        chat_id = queues.keys.first
        next unless chat_id

        queues[chat_id]&.push(
          Nanobot::Bus::OutboundMessage.new(channel: 'gateway', chat_id: chat_id, content: 'hi there')
        )
      end

      test_channel.handle_http_request(request, response)

      expect(response).to have_received(:content_type=).with('application/json')
      expect(response).to have_received(:body=) do |body|
        parsed = JSON.parse(body)
        expect(parsed['response']).to eq('hi there')
        expect(parsed['chat_id']).to be_a(String)
      end
    end

    it 'uses provided chat_id when present' do
      allow(bus).to receive(:publish_inbound)
      req = double('request',
                   request_method: 'POST',
                   body: '{"message":"hello","chat_id":"my-session-1"}',
                   :[] => nil)

      Thread.new do
        sleep 0.05
        queues = test_channel.instance_variable_get(:@response_queues)
        queues['my-session-1']&.push(
          Nanobot::Bus::OutboundMessage.new(channel: 'gateway', chat_id: 'my-session-1', content: 'ok')
        )
      end

      test_channel.handle_http_request(req, response)

      expect(response).to have_received(:body=) do |body|
        parsed = JSON.parse(body)
        expect(parsed['chat_id']).to eq('my-session-1')
      end
    end

    it 'rejects non-POST requests with 405' do
      req = double('request', request_method: 'GET')

      test_channel.handle_http_request(req, response)

      expect(response).to have_received(:status=).with(405)
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)['error']).to eq('Method not allowed')
      end
    end

    it 'returns 400 for missing message field' do
      allow(bus).to receive(:publish_inbound)
      req = double('request',
                   request_method: 'POST',
                   body: '{"text":"hello"}',
                   :[] => nil)

      test_channel.handle_http_request(req, response)

      expect(response).to have_received(:status=).with(400)
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)['error']).to eq('Missing "message" field')
      end
    end

    it 'returns 400 for invalid JSON' do
      req = double('request',
                   request_method: 'POST',
                   body: 'not json at all',
                   :[] => nil)

      test_channel.handle_http_request(req, response)

      expect(response).to have_received(:status=).with(400)
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)['error']).to eq('Invalid JSON')
      end
    end
  end

  describe 'private #handle_health' do
    it 'returns status ok as JSON' do
      test_channel.handle_health(response)

      expect(response).to have_received(:content_type=).with('application/json')
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)).to eq({ 'status' => 'ok' })
      end
    end
  end

  describe 'private #authorized?' do
    it 'returns true when no auth_token is configured' do
      req = double('request', :[] => nil)
      expect(test_channel.authorized?(req)).to be true
    end

    context 'with auth_token configured' do
      let(:config) { double('config', allow_from: [], port: 0, host: '127.0.0.1', auth_token: 'secret-token') }

      it 'returns true for valid Bearer token' do
        req = double('request')
        allow(req).to receive(:[]).with('Authorization').and_return('Bearer secret-token')

        expect(test_channel.authorized?(req)).to be true
      end

      it 'returns false for invalid token' do
        req = double('request')
        allow(req).to receive(:[]).with('Authorization').and_return('Bearer wrong-token')

        expect(test_channel.authorized?(req)).to be false
      end

      it 'returns false for missing Authorization header' do
        req = double('request')
        allow(req).to receive(:[]).with('Authorization').and_return(nil)

        expect(test_channel.authorized?(req)).to be false
      end
    end
  end

  describe 'private #error_response' do
    it 'sets status, content type, and error body' do
      test_channel.error_response(response, 500, 'Internal error')

      expect(response).to have_received(:status=).with(500)
      expect(response).to have_received(:content_type=).with('application/json')
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)).to eq({ 'error' => 'Internal error' })
      end
    end
  end

  describe 'authentication in HTTP request flow' do
    let(:config) { double('config', allow_from: [], port: 0, host: '127.0.0.1', auth_token: 'my-token') }

    it 'rejects requests with invalid auth token with 401' do
      req = double('request', request_method: 'POST', body: '{"message":"hello"}')
      allow(req).to receive(:[]).with('Authorization').and_return('Bearer bad-token')

      test_channel.handle_http_request(req, response)

      expect(response).to have_received(:status=).with(401)
      expect(response).to have_received(:body=) do |body|
        expect(JSON.parse(body)['error']).to eq('Unauthorized')
      end
    end

    it 'accepts requests with valid auth token' do
      allow(bus).to receive(:publish_inbound)
      req = double('request', request_method: 'POST', body: '{"message":"hello"}')
      allow(req).to receive(:[]).with('Authorization').and_return('Bearer my-token')

      Thread.new do
        sleep 0.05
        queues = test_channel.instance_variable_get(:@response_queues)
        chat_id = queues.keys.first
        next unless chat_id

        queues[chat_id]&.push(
          Nanobot::Bus::OutboundMessage.new(channel: 'gateway', chat_id: chat_id, content: 'ok')
        )
      end

      test_channel.handle_http_request(req, response)

      expect(bus).to have_received(:publish_inbound)
    end
  end
end
