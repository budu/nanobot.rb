# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/nanobot/agent/tools/filesystem'

RSpec.describe Nanobot::Agent::Tools::ReadFile do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(allowed_dir: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#name' do
    it 'returns tool name' do
      # RubyLLM generates name from class name
      expect(tool.name).to include('read_file')
    end
  end

  describe '#description' do
    it 'returns description' do
      expect(tool.description).to be_a(String)
    end
  end

  describe '#execute' do
    it 'reads file contents' do
      file_path = File.join(workspace, 'test.txt')
      File.write(file_path, 'Test content')

      result = tool.execute(path: file_path)
      expect(result).to eq('Test content')
    end

    it 'returns error for non-existent file' do
      result = tool.execute(path: File.join(workspace, 'nonexistent.txt'))
      expect(result).to include('Error: File not found')
    end

    it 'returns error for directory' do
      result = tool.execute(path: workspace)
      expect(result).to include('Error: Path is not a file')
    end

    it 'enforces directory restrictions' do
      outside_file = File.join(Dir.tmpdir, 'outside.txt')
      File.write(outside_file, 'Outside content')

      result = tool.execute(path: outside_file)
      expect(result).to include('Error: Access denied')

      File.delete(outside_file)
    end

    it 'allows access within allowed directory' do
      file_path = File.join(workspace, 'allowed.txt')
      File.write(file_path, 'Allowed content')

      result = tool.execute(path: file_path)
      expect(result).to eq('Allowed content')
    end

    it 'works without directory restrictions' do
      unrestricted_tool = described_class.new
      file_path = File.join(Dir.tmpdir, 'test.txt')
      File.write(file_path, 'Content')

      result = unrestricted_tool.execute(path: file_path)
      expect(result).to eq('Content')

      File.delete(file_path)
    end
  end
end

RSpec.describe Nanobot::Agent::Tools::WriteFile do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(allowed_dir: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#execute' do
    it 'writes content to file' do
      file_path = File.join(workspace, 'new.txt')

      result = tool.execute(path: file_path, content: 'New content')
      expect(result).to include('Successfully wrote')
      expect(File.read(file_path)).to eq('New content')
    end

    it 'overwrites existing file' do
      file_path = File.join(workspace, 'existing.txt')
      File.write(file_path, 'Old content')

      tool.execute(path: file_path, content: 'New content')
      expect(File.read(file_path)).to eq('New content')
    end

    it 'creates directories if needed' do
      file_path = File.join(workspace, 'nested', 'dir', 'file.txt')

      result = tool.execute(path: file_path, content: 'Content')
      expect(result).to include('Successfully wrote')
      expect(File.exist?(file_path)).to be true
    end

    it 'enforces directory restrictions' do
      outside_path = File.join(Dir.tmpdir, 'outside.txt')

      result = tool.execute(path: outside_path, content: 'Content')
      expect(result).to include('Error: Access denied')
    end
  end
end

RSpec.describe Nanobot::Agent::Tools::EditFile do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(allowed_dir: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#execute' do
    it 'replaces old_text with new_text' do
      file_path = File.join(workspace, 'edit.txt')
      File.write(file_path, 'Hello world')

      result = tool.execute(path: file_path, old_text: 'world', new_text: 'Ruby')
      expect(result).to include('Successfully edited')
      expect(File.read(file_path)).to eq('Hello Ruby')
    end

    it 'returns error if file not found' do
      result = tool.execute(
        path: File.join(workspace, 'nonexistent.txt'),
        old_text: 'old',
        new_text: 'new'
      )
      expect(result).to include('Error: File not found')
    end

    it 'returns error if old_text not found' do
      file_path = File.join(workspace, 'edit.txt')
      File.write(file_path, 'Hello world')

      result = tool.execute(path: file_path, old_text: 'missing', new_text: 'new')
      expect(result).to include('Error: Text not found')
    end

    it 'returns error for multiple occurrences' do
      file_path = File.join(workspace, 'edit.txt')
      File.write(file_path, 'foo bar foo')

      result = tool.execute(path: file_path, old_text: 'foo', new_text: 'baz')
      expect(result).to include('Error: Text appears 2 times')
    end

    it 'enforces directory restrictions' do
      result = tool.execute(
        path: '/tmp/outside.txt',
        old_text: 'old',
        new_text: 'new'
      )
      expect(result).to include('Error: Access denied')
    end
  end
end

RSpec.describe Nanobot::Agent::Tools::ListDir do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(allowed_dir: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#execute' do
    it 'lists directory contents' do
      FileUtils.mkdir_p(File.join(workspace, 'subdir'))
      File.write(File.join(workspace, 'file1.txt'), 'content')
      File.write(File.join(workspace, 'file2.txt'), 'content')

      result = tool.execute(path: workspace)
      expect(result).to include('file1.txt')
      expect(result).to include('file2.txt')
      expect(result).to include('subdir/')
    end

    it 'returns error for non-existent directory' do
      result = tool.execute(path: File.join(workspace, 'nonexistent'))
      expect(result).to include('Error: Directory not found')
    end

    it 'returns error for file path' do
      file_path = File.join(workspace, 'file.txt')
      File.write(file_path, 'content')

      result = tool.execute(path: file_path)
      expect(result).to include('Error: Path is not a directory')
    end

    it 'shows empty directory message' do
      result = tool.execute(path: workspace)
      expect(result).to eq('(empty directory)')
    end

    it 'enforces directory restrictions' do
      result = tool.execute(path: '/tmp')
      expect(result).to include('Error: Access denied')
    end
  end
end
