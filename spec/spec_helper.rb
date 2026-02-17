# frozen_string_literal: true

require 'amazing_print'
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  add_group 'Agent', 'lib/nanobot/agent'
  add_group 'Bus', 'lib/nanobot/bus'
  add_group 'Channels', 'lib/nanobot/channels'
  add_group 'Scheduler', 'lib/nanobot/scheduler'
  add_group 'Tools', 'lib/nanobot/agent/tools'
  minimum_coverage 90

  # Print coverage summary to console
  at_exit do
    SimpleCov.result.format!
    SimpleCov.result.files.each do |file|
      if file.covered_percent < SimpleCov.minimum_coverage[:line]
        puts "  #{file.filename.gsub(%r{^.*/nanobot\.rb/}, '')}: #{file.covered_percent.round(2)}%" # rubocop:disable RSpec/Output
      end
    end
  end
end

require 'bundler/setup'
require 'nanobot'
require 'webmock/rspec'
require 'timecop'
require 'logger'

# Helper method to create a test logger
# By default, logs are suppressed unless DEBUG_TESTS env var is set
def test_logger
  if ENV['DEBUG_TESTS']
    Logger.new($stdout)
  else
    Logger.new(IO::NULL)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up test files after each test
  config.after do
    Timecop.return
  end
end
