# frozen_string_literal: true

require_relative 'lib/nanobot/version'

Gem::Specification.new do |spec|
  spec.name          = 'nanobot'
  spec.version       = Nanobot::VERSION
  spec.authors       = ['Nanobot Contributors']
  spec.email         = ['nanobot@example.com']

  spec.summary       = 'Ultra-lightweight personal AI assistant framework'
  spec.description   = 'A minimalist AI agent framework with multi-channel support, ' \
                       'tool calling, and extensible architecture'
  spec.homepage      = 'https://github.com/yourusername/nanobot.rb'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 4.0.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{bin,lib}/**/*') + %w[README.md LICENSE Gemfile]
  spec.bindir = 'bin'
  spec.executables = ['nanobot']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'faraday', '~> 2.7'
  spec.add_dependency 'json', '~> 2.6'
  spec.add_dependency 'logger', '~> 1.5'
  spec.add_dependency 'nokogiri', '~> 1.15'
  spec.add_dependency 'ruby_llm' # RubyLLM gem
  spec.add_dependency 'thor', '~> 1.3'
end
