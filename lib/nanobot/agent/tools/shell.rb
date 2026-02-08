# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'ruby_llm'

module Nanobot
  module Agent
    module Tools
      # Tool for executing shell commands with security restrictions
      class Exec < RubyLLM::Tool
        description 'Execute a shell command and return its output'
        param :command, desc: 'Shell command to execute', required: true

        # Dangerous command patterns that should be blocked
        DENY_PATTERNS = [
          /rm\s+-rf/i,
          %r{rmdir\s+/s}i,
          /format\s/i,
          /mkfs/i,
          /shutdown/i,
          /reboot/i,
          /halt/i,
          /poweroff/i,
          /dd\s+if=/i,
          /:\(\)\{\s*:\|:&\s*\};:/, # fork bomb
          %r{>/dev/sd[a-z]}i # writing to disk devices
        ].freeze

        def initialize(working_dir: nil, timeout: 60, restrict_to_workspace: false)
          super()
          @working_dir = working_dir ? Pathname.new(working_dir).expand_path.to_s : Dir.pwd
          @timeout = timeout
          @restrict_to_workspace = restrict_to_workspace
        end

        def execute(command:)
          # Security: Check for dangerous patterns
          return 'Error: Command blocked for security reasons. Contains dangerous patterns.' if dangerous?(command)

          begin
            # Execute command with timeout
            stdout, stderr, status = execute_with_timeout(command)

            # Format output
            output = []
            output << "Exit code: #{status.exitstatus}"

            if stdout && !stdout.empty?
              output << "\nStdout:"
              output << stdout
            end

            if stderr && !stderr.empty?
              output << "\nStderr:"
              output << stderr
            end

            output.join("\n")
          rescue Timeout::Error
            "Error: Command timed out after #{@timeout} seconds"
          rescue StandardError => e
            "Error executing command: #{e.message}"
          end
        end

        private

        def dangerous?(command)
          DENY_PATTERNS.any? { |pattern| command.match?(pattern) }
        end

        def execute_with_timeout(command)
          stdout_str = nil
          stderr_str = nil
          status = nil

          Timeout.timeout(@timeout) do
            stdout_str, stderr_str, status = Open3.capture3(
              command,
              chdir: @working_dir
            )
          end

          [stdout_str, stderr_str, status]
        end
      end
    end
  end
end
