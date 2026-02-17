# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'File tools', :integration do
  shared_examples 'file tool scenarios' do |provider_label:|
    let(:agent) { create_integration_agent(provider: @provider, workspace: @workspace) }

    describe 'read file' do
      before do
        File.write(workspace_path('test.txt'), 'integration test content 7x42')
      end

      it "reads a file and includes its content [#{provider_label}]", scenario: :tool_read_file do
        response = agent_send(
          'Read the file test.txt in your workspace and tell me exactly what it contains.'
        )
        expect(response).to include('integration test content 7x42')
      end
    end

    describe 'write file' do
      it "writes a file when asked [#{provider_label}]", scenario: :tool_write_file do
        agent_send(
          'Write a file called output.txt in your workspace with the exact content: nanobot integration test'
        )
        file_path = workspace_path('output.txt')
        expect(File.exist?(file_path)).to be true
        expect(File.read(file_path)).to include('nanobot integration test')
      end
    end

    describe 'edit file' do
      before do
        File.write(workspace_path('edit_me.txt'), "line one\nreplace this line\nline three\n")
      end

      it "edits a file when asked [#{provider_label}]", scenario: :tool_edit_file do
        agent_send(
          'Edit the file edit_me.txt in your workspace: replace the text "replace this line" ' \
          'with "line two updated".'
        )
        content = File.read(workspace_path('edit_me.txt'))
        expect(content).to include('line two updated')
        expect(content).not_to include('replace this line')
      end
    end

    describe 'list directory' do
      before do
        File.write(workspace_path('file_a.txt'), 'a')
        File.write(workspace_path('file_b.txt'), 'b')
      end

      it "lists directory contents [#{provider_label}]", scenario: :tool_list_dir do
        response = agent_send('List the files in your workspace directory.')
        expect(response).to include('file_a.txt')
        expect(response).to include('file_b.txt')
      end
    end
  end

  Nanobot::Integration::DSL.include_scenarios(self, 'file tool scenarios')
end
