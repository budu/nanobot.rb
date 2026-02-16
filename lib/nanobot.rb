# frozen_string_literal: true

require_relative 'nanobot/version'
require_relative 'nanobot/bus/events'
require_relative 'nanobot/bus/message_bus'
require_relative 'nanobot/agent/context'
require_relative 'nanobot/agent/memory'
require_relative 'nanobot/session/manager'
require_relative 'nanobot/providers/base'
require_relative 'nanobot/providers/rubyllm_provider'
require_relative 'nanobot/agent/loop'
require_relative 'nanobot/config/schema'
require_relative 'nanobot/config/loader'
require_relative 'nanobot/channels/base'
require_relative 'nanobot/channels/manager'

# Multi-channel AI chatbot framework powered by RubyLLM
module Nanobot
  # Base error class for all Nanobot errors
  class Error < StandardError; end
end
