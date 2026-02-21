# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'ruby_llm'

module Nanobot
  module Agent
    module Tools
      # Tool for executing shell commands.
      #
      # IMPORTANT: The DENY_PATTERNS list below is accident prevention, not a
      # security boundary. It catches common destructive typos and mistakes but
      # is trivially bypassed (nested shells, alternative interpreters, creative
      # flag combinations, data exfiltration via curl/wget, etc.).
      # For actual isolation, use OS-level sandboxing (bubblewrap, containers).
      class Exec < RubyLLM::Tool
        description 'Execute a shell command and return its output'
        param :command, desc: 'Shell command to execute', required: true

        # Common destructive patterns blocked as accident prevention.
        # NOT a security boundary — see class comment above.
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

        # @param working_dir [String, nil] directory to run commands in (defaults to cwd)
        # @param timeout [Integer] maximum seconds before a command is killed
        # @param restrict_to_workspace [Boolean] when true, block commands referencing paths outside working_dir
        def initialize(working_dir: nil, timeout: 60, restrict_to_workspace: false)
          super()
          @working_dir = working_dir ? Pathname.new(working_dir).expand_path.to_s : Dir.pwd
          @timeout = timeout
          @restrict_to_workspace = restrict_to_workspace
        end

        # Execute a shell command and return its combined output.
        # @param command [String] shell command to execute
        # @return [String] formatted output with exit code, stdout, and stderr
        def execute(command:)
          # Accident prevention: block common destructive patterns
          return 'Error: Command blocked — matches a known destructive pattern.' if dangerous?(command)

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

        # Check if a command matches any blocked pattern.
        # @param command [String] command string to check
        # @return [Boolean]
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

        # Run a command via Open3, killing the process group on timeout.
        # @param command [String] shell command to execute
        # @return [Array(String, String, Process::Status)] stdout, stderr, and exit status
        # @raise [Timeout::Error] if the command exceeds the configured timeout
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

        # Send TERM then KILL to an entire process group.
        # @param pid [Integer] process ID whose group to kill
        def kill_process_group(pid)
          pgid = Process.getpgid(pid)
          Process.kill('-TERM', pgid)
          # Give the process group a moment to terminate gracefully
          sleep(0.5)
          Process.kill('-KILL', pgid) if process_alive?(pid)
        rescue Errno::ESRCH, Errno::EPERM
          # Process already exited or not permitted
        end

        # Check whether a process is still running.
        # @param pid [Integer] process ID to check
        # @return [Boolean]
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
