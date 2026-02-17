# frozen_string_literal: true

require_relative 'integration_helper'

# rubocop:disable RSpec/DescribeClass, RSpec/InstanceVariable
RSpec.describe 'Agent comprehension', :integration do
  shared_examples 'comprehension scenarios' do |provider_label:|
    let(:agent) { create_integration_agent(provider: @provider, workspace: @workspace) }

    describe 'simple conversation' do
      it "responds to a greeting [#{provider_label}]", scenario: :simple_greeting do
        response = agent_send('Say hello in exactly one sentence.')
        expect(response).to be_a(String)
        expect(response.strip.length).to be > 0
      end

      it "answers a factual question [#{provider_label}]", scenario: :factual_question do
        response = agent_send('What is 2 + 2? Reply with just the number.')
        expect(response).to match(/4/)
      end
    end

    describe 'tool use: read file' do
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

    describe 'tool use: write file' do
      it "writes a file when asked [#{provider_label}]", scenario: :tool_write_file do
        agent_send(
          'Write a file called output.txt in your workspace with the exact content: nanobot integration test'
        )
        file_path = workspace_path('output.txt')
        expect(File.exist?(file_path)).to be true
        expect(File.read(file_path)).to include('nanobot integration test')
      end
    end

    describe 'tool use: edit file' do
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

    describe 'tool use: exec' do
      it "runs a shell command and reports output [#{provider_label}]", scenario: :tool_exec do
        response = agent_send('Run the command "echo nanobot_exec_test_8675" and tell me the output.')
        expect(response).to include('nanobot_exec_test_8675')
      end
    end

    describe 'tool use: list directory' do
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

    describe 'tool use: schedule' do
      let(:schedule_store_path) { File.join(@workspace, 'schedules.json') }
      let(:schedule_store) { Nanobot::Scheduler::ScheduleStore.new(path: schedule_store_path) }
      let(:scheduling_agent) do
        create_integration_agent(provider: @provider, workspace: @workspace, schedule_store: schedule_store)
      end

      it "creates a schedule when asked [#{provider_label}]", scenario: :tool_schedule_add do
        response = scheduling_agent.process_direct(
          'Set a reminder for 30 minutes from now to check my email. ' \
          'Use the schedule_add tool with kind "every" and expression "30m".',
          chat_id: @integration_chat_id
        )
        expect(response).to be_a(String)
        expect(schedule_store.list.size).to eq(1)
        expect(schedule_store.list.first.kind).to eq('every')
        expect(schedule_store.list.first.expression).to eq('30m')
      end

      it "lists schedules when asked [#{provider_label}]", scenario: :tool_schedule_list do
        schedule_store.add(kind: 'cron', expression: '0 9 * * *', prompt: 'morning standup reminder')
        response = scheduling_agent.process_direct(
          'List all my scheduled tasks.',
          chat_id: @integration_chat_id
        )
        expect(response).to include('morning standup')
      end

      it "removes a schedule when asked [#{provider_label}]", scenario: :tool_schedule_remove do
        schedule = schedule_store.add(kind: 'every', expression: '2h', prompt: 'check server status')
        short_id = schedule.id[0..7]
        scheduling_agent.process_direct(
          "Remove the scheduled task with ID #{short_id}.",
          chat_id: @integration_chat_id
        )
        expect(schedule_store.list).to be_empty
      end
    end

    describe 'multi-turn conversation' do
      it "maintains context across turns [#{provider_label}]", scenario: :multi_turn do
        agent_send('Remember this code: ALPHA-9923. I will ask about it later.')
        response = agent_send('What was the code I asked you to remember?')
        expect(response).to include('ALPHA-9923')
      end
    end

    describe 'slash commands', :skip_scenario_tracking do
      it "handles /help command [#{provider_label}]" do
        response = agent_send('/help')
        expect(response).to include('Available commands:')
        expect(response).to include('/new')
        expect(response).to include('/help')
      end

      it "handles /new command [#{provider_label}]" do
        response = agent_send('/new')
        expect(response).to eq('New session started.')
      end
    end
  end

  context 'when recording', if: Nanobot::Integration::Config.record_mode? do
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      config = Nanobot::Config::Loader.load
      provider_name = Nanobot::Integration::Config.provider_name
      model_name = Nanobot::Integration::Config.model_name

      provider_config = config.providers.send(provider_name.to_sym) if
        config.providers.respond_to?(provider_name.to_sym)
      api_key = provider_config&.api_key
      api_base = provider_config&.api_base

      raise "No API key configured for provider '#{provider_name}' in ~/.nanobot/config.json" unless api_key

      real_provider = Nanobot::Providers::RubyLLMProvider.new(
        api_key: api_key,
        api_base: api_base,
        default_model: model_name,
        provider: provider_name,
        logger: test_logger
      )

      @provider = Nanobot::Integration::RecordingProvider.new(real_provider)
    end

    before do
      @workspace = Dir.mktmpdir('nanobot-integration-')
    end

    after do
      FileUtils.rm_rf(@workspace) if @workspace
    end

    after(:all) do # rubocop:disable RSpec/BeforeAfterAll
      path = @provider.save_fixture
      puts "\nRecorded integration fixture: #{path}" # rubocop:disable RSpec/Output
    end

    it_behaves_like 'comprehension scenarios',
                    provider_label: "recording #{Nanobot::Integration::Config.provider_name}/" \
                                    "#{Nanobot::Integration::Config.model_name}"
  end

  # rubocop:disable RSpec/LeakyLocalVariable
  context 'when replaying' do
    fixtures = Nanobot::Integration::Config.fixture_files

    if fixtures.empty?
      it 'has no recorded fixtures (run with NANOBOT_INTEGRATION_RECORD=true to record)' do
        pending 'No fixture files found in spec/fixtures/integration_responses/. ' \
                'To record fixtures: ' \
                '1) Configure an API key in ~/.nanobot/config.json ' \
                '(e.g. {"providers":{"anthropic":{"api_key":"sk-ant-..."}}}), then ' \
                '2) Run: NANOBOT_INTEGRATION_RECORD=true NANOBOT_INTEGRATION_PROVIDER=anthropic ' \
                'NANOBOT_INTEGRATION_MODEL=claude-haiku-4-5 bundle exec rspec spec/integration'
        expect(fixtures).not_to be_empty
      end
    end

    fixtures.each do |fixture_path|
      fixture_data = JSON.parse(File.read(fixture_path), symbolize_names: true)
      fixture_meta = fixture_data[:metadata]
      label = "#{fixture_meta[:provider]}/#{fixture_meta[:model]} " \
              "(#{File.basename(fixture_path)})"

      context "with #{label}", unless: Nanobot::Integration::Config.record_mode? do
        before(:all) do # rubocop:disable RSpec/BeforeAfterAll
          @provider = Nanobot::Integration::ReplayProvider.new(fixture_path)
        end

        before do
          @workspace = Dir.mktmpdir('nanobot-integration-')
        end

        after do
          FileUtils.rm_rf(@workspace) if @workspace
        end

        it_behaves_like 'comprehension scenarios', provider_label: label
      end
    end
  end
  # rubocop:enable RSpec/LeakyLocalVariable
end
# rubocop:enable RSpec/DescribeClass, RSpec/InstanceVariable
