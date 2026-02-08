# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/nanobot/agent/tools/shell'

RSpec.describe Nanobot::Agent::Tools::Exec do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(working_dir: workspace, timeout: 5) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#name' do
    it 'returns tool name' do
      # RubyLLM generates name from class name
      expect(tool.name).to include('exec')
    end
  end

  describe '#description' do
    it 'returns description' do
      expect(tool.description).to be_a(String)
    end
  end

  describe '#execute' do
    it 'executes simple command' do
      result = tool.execute(command: 'echo "Hello"')
      expect(result).to include('Exit code: 0')
      expect(result).to include('Hello')
    end

    it 'captures stdout' do
      result = tool.execute(command: 'echo "Test output"')
      expect(result).to include('Stdout:')
      expect(result).to include('Test output')
    end

    it 'captures stderr' do
      result = tool.execute(command: 'echo "Error message" >&2')
      expect(result).to include('Stderr:')
      expect(result).to include('Error message')
    end

    it 'reports exit code' do
      result = tool.execute(command: 'exit 42')
      expect(result).to include('Exit code: 42')
    end

    it 'uses specified working directory' do
      File.write(File.join(workspace, 'test.txt'), 'content')
      result = tool.execute(command: 'ls test.txt')
      expect(result).to include('test.txt')
    end

    it 'blocks dangerous rm -rf commands' do
      result = tool.execute(command: 'rm -rf /')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'blocks shutdown commands' do
      result = tool.execute(command: 'shutdown now')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'blocks reboot commands' do
      result = tool.execute(command: 'reboot')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'blocks format commands' do
      result = tool.execute(command: 'format c:')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'blocks dd commands to devices' do
      result = tool.execute(command: 'dd if=/dev/zero of=/dev/sda')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'blocks fork bombs' do
      result = tool.execute(command: ':(){:|:&};:')
      expect(result).to include('Error: Command blocked for security reasons')
    end

    it 'handles timeout' do
      # Use very short timeout (100ms) with a command that takes longer (200ms)
      short_timeout_tool = described_class.new(working_dir: workspace, timeout: 0.1)

      # Temporarily disable thread error reporting to avoid IOError warnings
      original_report = Thread.report_on_exception
      Thread.report_on_exception = false

      result = short_timeout_tool.execute(command: 'sleep 0.2')
      expect(result).to include('Error: Command timed out')
    ensure
      Thread.report_on_exception = original_report if defined?(original_report)
    end

    it 'handles execution errors' do
      result = tool.execute(command: 'nonexistent_command_12345')
      # Should not crash, may show error in stderr or exit code
      expect(result).to be_a(String)
    end

    it 'uses default working directory when not specified' do
      default_tool = described_class.new
      result = default_tool.execute(command: 'pwd')
      expect(result).to include('Exit code: 0')
    end

    it 'accepts restrict_to_workspace parameter' do
      restricted_tool = described_class.new(
        working_dir: workspace,
        restrict_to_workspace: true
      )
      result = restricted_tool.execute(command: 'echo test')
      expect(result).to include('test')
    end
  end
end
