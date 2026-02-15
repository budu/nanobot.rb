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

    it 'returns formatted results for a successful search' do
      response_body = {
        web: {
          results: [
            { title: 'Ruby Language', url: 'https://ruby-lang.org', description: 'The Ruby programming language' },
            { title: 'RubyGems', url: 'https://rubygems.org', description: 'Find and install Ruby gems' }
          ]
        }
      }.to_json

      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'ruby programming')
        )
        .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

      result = tool.execute(query: 'ruby programming')
      expect(result).to include('Search results:')
      expect(result).to include('1. Ruby Language')
      expect(result).to include('URL: https://ruby-lang.org')
      expect(result).to include('The Ruby programming language')
      expect(result).to include('2. RubyGems')
      expect(result).to include('URL: https://rubygems.org')
    end

    it 'returns no results message when results are empty' do
      response_body = { web: { results: [] } }.to_json

      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'xyznonexistent')
        )
        .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

      result = tool.execute(query: 'xyznonexistent')
      expect(result).to eq('No results found')
    end

    it 'handles API error responses gracefully' do
      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'test')
        )
        .to_return(status: 500, body: 'Internal Server Error')

      result = tool.execute(query: 'test')
      expect(result).to include('Error performing web search')
    end

    it 'handles network errors gracefully' do
      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'test')
        )
        .to_raise(Faraday::ConnectionFailed.new('connection failed'))

      result = tool.execute(query: 'test')
      expect(result).to include('Error performing web search')
    end

    it 'passes count parameter to the API' do
      response_body = {
        web: {
          results: [
            { title: 'Result 1', url: 'https://example.com/1', description: 'First result' }
          ]
        }
      }.to_json

      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'test', 'count' => '3')
        )
        .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

      result = tool.execute(query: 'test', count: 3)
      expect(result).to include('Search results:')
      expect(result).to include('1. Result 1')
    end

    it 'handles results without description' do
      response_body = {
        web: {
          results: [
            { title: 'No Description', url: 'https://example.com/nodesc' }
          ]
        }
      }.to_json

      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          headers: { 'X-Subscription-Token' => api_key },
          query: hash_including('q' => 'test')
        )
        .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

      result = tool.execute(query: 'test')
      expect(result).to include('1. No Description')
      expect(result).to include('URL: https://example.com/nodesc')
    end
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
