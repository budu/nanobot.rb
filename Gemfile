# frozen_string_literal: true

source 'https://rubygems.org'

ruby '~> 4.0.1'

gem 'faraday', '~> 2.7' # HTTP & Network
gem 'fugit', '~> 1.8' # Cron/duration/timestamp parsing
gem 'json', '~> 2.6' # JSON & Serialization
gem 'logger', '~> 1.5' # Logging
gem 'nokogiri', '~> 1.15' # Web parsing
gem 'ruby_llm' # LLM Integration
gem 'thor', '~> 1.3' # CLI & Commands
gem 'webrick', '~> 1.8' # HTTP Gateway channel

# Optional channel dependencies (install as needed)
gem 'discordrb', require: false
gem 'mail', require: false
gem 'slack-ruby-client', require: false
gem 'telegram-bot-ruby', require: false

# Development & Testing
group :development, :test do
  gem 'amazing_print'
  gem 'debug', '~> 1.9'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.84'
  gem 'rubocop-rspec', '~> 3.0', require: false
  gem 'simplecov', '~> 0.22', require: false
  gem 'timecop', '~> 0.9'
  gem 'webmock', '~> 3.19'
end
