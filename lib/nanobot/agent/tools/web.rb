# frozen_string_literal: true

require 'faraday'
require 'ipaddr'
require 'json'
require 'nokogiri'
require 'resolv'
require 'ruby_llm'
require 'uri'

module Nanobot
  module Agent
    module Tools
      # Tool for web search using Brave Search API
      class WebSearch < RubyLLM::Tool
        description 'Search the web using Brave Search API'
        param :query, desc: 'Search query', required: true
        param :count, type: 'integer', desc: 'Number of results to return (default: 5)', required: false

        # @param api_key [String, nil] Brave Search API key (falls back to BRAVE_SEARCH_API_KEY env var)
        def initialize(api_key: nil)
          super()
          @api_key = api_key || ENV.fetch('BRAVE_SEARCH_API_KEY', nil)
        end

        # Perform a web search and return formatted results.
        # @param query [String] search query
        # @param count [Integer] number of results to return
        # @return [String] formatted search results or error message
        def execute(query:, count: 5)
          return 'Error: Brave Search API key not configured' unless @api_key

          begin
            response = search(query, count)
            format_results(response)
          rescue StandardError => e
            "Error performing web search: #{e.message}"
          end
        end

        SEARCH_OPEN_TIMEOUT = 10
        SEARCH_READ_TIMEOUT = 15

        private

        # Call the Brave Search API.
        # @param query [String] search query
        # @param count [Integer] number of results
        # @return [Hash] parsed JSON response
        def search(query, count)
          conn = Faraday.new(url: 'https://api.search.brave.com') do |f|
            f.request :url_encoded
            f.options.open_timeout = SEARCH_OPEN_TIMEOUT
            f.options.timeout = SEARCH_READ_TIMEOUT
            f.adapter Faraday.default_adapter
          end

          response = conn.get('/res/v1/web/search') do |req|
            req.headers['X-Subscription-Token'] = @api_key
            req.headers['Accept'] = 'application/json'
            req.params['q'] = query
            req.params['count'] = count
          end

          JSON.parse(response.body)
        end

        # Format API response into a human-readable string.
        # @param response [Hash] parsed Brave Search API response
        # @return [String] formatted results
        def format_results(response)
          results = response['web']['results'] || []

          return 'No results found' if results.empty?

          output = ['Search results:']
          results.each_with_index do |result, idx|
            output << "\n#{idx + 1}. #{result['title']}"
            output << "   URL: #{result['url']}"
            output << "   #{result['description']}" if result['description']
          end

          output.join("\n")
        end
      end

      # Tool for fetching and parsing web pages
      class WebFetch < RubyLLM::Tool
        description 'Fetch and parse a web page, returning its main content'
        param :url, desc: 'URL of the web page to fetch', required: true

        MAX_RESPONSE_BYTES = 1_048_576 # 1 MB
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 15
        MAX_REDIRECTS = 5

        PRIVATE_RANGES = [
          IPAddr.new('0.0.0.0/8'),
          IPAddr.new('127.0.0.0/8'),
          IPAddr.new('10.0.0.0/8'),
          IPAddr.new('172.16.0.0/12'),
          IPAddr.new('192.168.0.0/16'),
          IPAddr.new('169.254.0.0/16'),
          IPAddr.new('::1/128'),
          IPAddr.new('fc00::/7'),
          IPAddr.new('fe80::/10')
        ].freeze

        USER_AGENT = 'Mozilla/5.0 (compatible)'

        # Fetch a web page, validate its URL, and return parsed content.
        # @param url [String] URL to fetch
        # @return [String] parsed page content or error message
        def execute(url:)
          validate_url!(url)
          content = fetch(url)
          parse_content(content, url)
        rescue StandardError => e
          "Error fetching web page: #{e.message}"
        end

        private

        # Validate a URL's scheme and ensure it does not resolve to a private address.
        # @param url [String] URL to validate
        # @raise [RuntimeError] if the URL is invalid or resolves to a private IP
        def validate_url!(url)
          uri = URI.parse(url)
          raise 'Invalid URL scheme: only http and https are allowed' unless %w[http https].include?(uri.scheme)
          raise 'URL must include a host' unless uri.host

          addresses = Resolv.getaddresses(uri.host)
          raise "Could not resolve hostname: #{uri.host}" if addresses.empty?

          addresses.each do |addr|
            ip = IPAddr.new(addr)
            if PRIVATE_RANGES.any? { |range| range.include?(ip) }
              raise "Access to private/internal address #{addr} is not allowed"
            end
          end
        end

        # Fetch URL content, following redirects up to MAX_REDIRECTS.
        # Truncates response bodies exceeding MAX_RESPONSE_BYTES.
        # @param url [String] URL to fetch
        # @return [String] response body
        # @raise [RuntimeError] on too many redirects or missing Location header
        def fetch(url)
          redirects = 0
          current_url = url

          loop do
            conn = Faraday.new do |f|
              f.options.open_timeout = OPEN_TIMEOUT
              f.options.timeout = READ_TIMEOUT
              f.adapter Faraday.default_adapter
            end

            response = conn.get(current_url) do |req|
              req.headers['User-Agent'] = USER_AGENT
            end

            if [301, 302, 303, 307, 308].include?(response.status)
              redirects += 1
              raise 'Too many redirects' if redirects > MAX_REDIRECTS

              current_url = response.headers['location']
              raise 'Redirect with no Location header' unless current_url

              validate_url!(current_url)
              next
            end

            body = response.body
            body = body.byteslice(0, MAX_RESPONSE_BYTES) if body && body.bytesize > MAX_RESPONSE_BYTES
            return body
          end
        end

        # Parse HTML and extract the main text content.
        # @param html [String] raw HTML response body
        # @param url [String] original URL (included in output)
        # @return [String] formatted title, URL, and extracted text
        def parse_content(html, url)
          doc = Nokogiri::HTML(html)

          # Remove script and style tags
          doc.css('script, style').each(&:remove)

          # Get title
          title = doc.at_css('title')&.text&.strip || 'Untitled'

          # Try to get main content
          main_content = doc.at_css('main, article, [role="main"]')
          main_content ||= doc.at_css('body')

          # Extract text
          text = main_content&.text || ''
          text = text.gsub(/\s+/, ' ').strip

          # Truncate if too long
          max_length = 5000
          text = "#{text[0...max_length]}... (truncated)" if text.length > max_length

          <<~OUTPUT
            Title: #{title}
            URL: #{url}

            Content:
            #{text}
          OUTPUT
        end
      end
    end
  end
end
