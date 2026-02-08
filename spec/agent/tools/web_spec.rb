# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/nanobot/agent/tools/web'

RSpec.describe Nanobot::Agent::Tools::WebSearch do
  let(:api_key) { 'test-brave-api-key' }
  let(:tool) { described_class.new(api_key: api_key) }

  describe '#initialize' do
    it 'accepts api_key' do
      expect(tool).to be_a(described_class)
    end

    it 'uses ENV variable when no api_key provided' do
      ENV['BRAVE_SEARCH_API_KEY'] = 'env-key'
      env_tool = described_class.new
      expect(env_tool).to be_a(described_class)
      ENV.delete('BRAVE_SEARCH_API_KEY')
    end
  end

  describe '#name' do
    it 'returns tool name' do
      # RubyLLM generates name from class name
      expect(tool.name).to include('web_search')
    end
  end

  describe '#description' do
    it 'returns description' do
      expect(tool.description).to be_a(String)
    end
  end

  describe '#execute' do
    it 'returns error when api_key not configured' do
      no_key_tool = described_class.new(api_key: nil)
      result = no_key_tool.execute(query: 'test')
      expect(result).to include('Error: Brave Search API key not configured')
    end

    # NOTE: Additional tests would require webmock stubs for the Brave API
    # These are skipped to avoid complex HTTP mocking in this test suite
  end
end

RSpec.describe Nanobot::Agent::Tools::WebFetch do
  let(:tool) { described_class.new }

  describe '#name' do
    it 'returns tool name' do
      # RubyLLM generates name from class name
      expect(tool.name).to include('web_fetch')
    end
  end

  describe '#description' do
    it 'returns description' do
      expect(tool.description).to be_a(String)
    end
  end

  describe '#execute' do
    it 'fetches and parses web page' do
      html = <<~HTML
        <html>
          <head><title>Test Page</title></head>
          <body>
            <main>
              <h1>Welcome</h1>
              <p>This is a test page.</p>
            </main>
          </body>
        </html>
      HTML

      stub_request(:get, 'https://example.com/page')
        .to_return(status: 200, body: html)

      result = tool.execute(url: 'https://example.com/page')
      expect(result).to include('Title: Test Page')
      expect(result).to include('Welcome')
      expect(result).to include('This is a test page')
    end

    it 'handles fetch errors gracefully' do
      stub_request(:get, 'https://example.com/error')
        .to_raise(Faraday::Error)

      result = tool.execute(url: 'https://example.com/error')
      expect(result).to include('Error fetching web page')
    end
  end
end
