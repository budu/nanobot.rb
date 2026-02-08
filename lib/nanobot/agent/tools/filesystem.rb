# frozen_string_literal: true

require 'fileutils'
require 'ruby_llm'

module Nanobot
  module Agent
    module Tools
      # Shared module for workspace directory sandboxing.
      # Ensures paths cannot escape the allowed directory via prefix tricks
      # (e.g., /home/user/workspace_evil bypassing /home/user/workspace).
      module WorkspaceSandbox
        private

        def within_allowed_dir?(path)
          return true unless @allowed_dir

          expanded = path.expand_path.to_s
          allowed = "#{@allowed_dir}/"
          expanded.start_with?(allowed) || expanded == @allowed_dir.to_s
        end
      end

      # Tool for reading file contents
      class ReadFile < RubyLLM::Tool
        include WorkspaceSandbox

        description 'Read the contents of a file'
        param :path, desc: 'Path to the file to read', required: true

        def initialize(allowed_dir: nil)
          super()
          @allowed_dir = allowed_dir ? Pathname.new(allowed_dir).expand_path : nil
        end

        def execute(path:)
          file_path = Pathname.new(path).expand_path

          # Security check
          if @allowed_dir && !within_allowed_dir?(file_path)
            return "Error: Access denied. Path is outside allowed directory: #{@allowed_dir}"
          end

          return "Error: File not found: #{path}" unless file_path.exist?
          return "Error: Path is not a file: #{path}" unless file_path.file?

          begin
            file_path.read
          rescue StandardError => e
            "Error reading file: #{e.message}"
          end
        end
      end

      # Tool for writing file contents
      class WriteFile < RubyLLM::Tool
        include WorkspaceSandbox

        description 'Write content to a file (creates new file or overwrites existing)'
        param :path, desc: 'Path to the file to write', required: true
        param :content, desc: 'Content to write to the file', required: true

        def initialize(allowed_dir: nil)
          super()
          @allowed_dir = allowed_dir ? Pathname.new(allowed_dir).expand_path : nil
        end

        def execute(path:, content:)
          file_path = Pathname.new(path).expand_path

          # Security check
          if @allowed_dir && !within_allowed_dir?(file_path)
            return "Error: Access denied. Path is outside allowed directory: #{@allowed_dir}"
          end

          begin
            # Ensure parent directory exists
            file_path.dirname.mkpath unless file_path.dirname.exist?

            file_path.write(content)
            "Successfully wrote #{content.length} characters to #{path}"
          rescue StandardError => e
            "Error writing file: #{e.message}"
          end
        end
      end

      # Tool for editing files by replacing text
      class EditFile < RubyLLM::Tool
        include WorkspaceSandbox

        description 'Edit a file by replacing old text with new text'
        param :path, desc: 'Path to the file to edit', required: true
        param :old_text, desc: 'Text to search for and replace', required: true
        param :new_text, desc: 'Text to replace with', required: true

        def initialize(allowed_dir: nil)
          super()
          @allowed_dir = allowed_dir ? Pathname.new(allowed_dir).expand_path : nil
        end

        def execute(path:, old_text:, new_text:)
          file_path = Pathname.new(path).expand_path

          # Security check
          if @allowed_dir && !within_allowed_dir?(file_path)
            return "Error: Access denied. Path is outside allowed directory: #{@allowed_dir}"
          end

          return "Error: File not found: #{path}" unless file_path.exist?
          return "Error: Path is not a file: #{path}" unless file_path.file?

          begin
            content = file_path.read

            return "Error: Text not found in file: #{old_text[0..50]}..." unless content.include?(old_text)

            # Check if old_text appears multiple times
            occurrences = content.scan(old_text).length
            return "Error: Text appears #{occurrences} times in file. Please be more specific." if occurrences > 1

            new_content = content.sub(old_text, new_text)
            file_path.write(new_content)

            "Successfully edited #{path}"
          rescue StandardError => e
            "Error editing file: #{e.message}"
          end
        end
      end

      # Tool for listing directory contents
      class ListDir < RubyLLM::Tool
        include WorkspaceSandbox

        description 'List contents of a directory'
        param :path, desc: 'Path to the directory to list', required: true

        def initialize(allowed_dir: nil)
          super()
          @allowed_dir = allowed_dir ? Pathname.new(allowed_dir).expand_path : nil
        end

        def execute(path:)
          dir_path = Pathname.new(path).expand_path

          # Security check
          if @allowed_dir && !within_allowed_dir?(dir_path)
            return "Error: Access denied. Path is outside allowed directory: #{@allowed_dir}"
          end

          return "Error: Directory not found: #{path}" unless dir_path.exist?
          return "Error: Path is not a directory: #{path}" unless dir_path.directory?

          begin
            entries = dir_path.children.map do |entry|
              if entry.directory?
                "#{entry.basename}/"
              else
                entry.basename.to_s
              end
            end.sort

            entries.empty? ? '(empty directory)' : entries.join("\n")
          rescue StandardError => e
            "Error listing directory: #{e.message}"
          end
        end
      end
    end
  end
end
