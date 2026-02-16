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

          # Best-effort workspace restriction.
          # NOTE: This is NOT a true security boundary.
          # Shell commands can bypass this check via aliases, symlinks, subshells, etc.  For
          # stronger isolation, use containers or OS-level sandboxing.
          if @restrict_to_workspace && command_leaves_workspace?(command)
            return "Error: Command appears to access paths outside the workspace (#{@working_dir}). " \
                   'Restricted to workspace directory.'
          end

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

        # Best-effort check for commands that reference paths outside the workspace.
        # Checks for absolute paths that don't start with the working directory.
        def command_leaves_workspace?(command)
          # Extract tokens that look like absolute paths
          absolute_paths = command.scan(%r{(?:^|\s|=)(/?(?:/[\w.*~-]+)+)}i).flatten
          absolute_paths.any? do |path|
            next false unless path.start_with?('/')

            expanded = File.expand_path(path)
            !expanded.start_with?(@working_dir)
          end
        end

        def execute_with_timeout(command)
          stdin, stdout, stderr, wait_thread = Open3.popen3(
            command,
            chdir: @working_dir,
            pgroup: true
          )
          stdin.close
          pid = wait_thread.pid

          # Read stdout/stderr in threads to avoid pipe deadlocks
          stdout_thread = Thread.new { stdout.read }
          stderr_thread = Thread.new { stderr.read }

          # Wait for process with timeout
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
          loop do
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if remaining <= 0
              # Timeout: kill the entire process group
              kill_process_group(pid)
              wait_thread.join
              raise Timeout::Error, "Command timed out after #{@timeout} seconds"
            end

            break unless wait_thread.alive?

            sleep([0.1, remaining].min)
          end

          stdout_str = stdout_thread.value
          stderr_str = stderr_thread.value
          status = wait_thread.value

          [stdout_str, stderr_str, status]
        ensure
          [stdout, stderr].each do |io|
            io&.close
          rescue StandardError # best-effort cleanup
            nil
          end
        end

        def kill_process_group(pid)
          pgid = Process.getpgid(pid)
          Process.kill('-TERM', pgid)
          # Give the process group a moment to terminate gracefully
          sleep(0.5)
          Process.kill('-KILL', pgid) if process_alive?(pid)
        rescue Errno::ESRCH, Errno::EPERM
          # Process already exited or not permitted
        end

        def process_alive?(pid)
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH, Errno::EPERM
          false
        end
      end
    end
  end
end
