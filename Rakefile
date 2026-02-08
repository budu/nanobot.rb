# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc 'Run rubocop'
task :rubocop do
  sh 'bundle exec rubocop'
end

desc 'Run console with nanobot loaded'
task :console do
  require 'pry'
  require_relative 'lib/nanobot'
  Pry.start
end

desc 'Clean generated files'
task :clean do
  FileUtils.rm_rf('pkg')
  FileUtils.rm_rf('.rspec_status')
end
