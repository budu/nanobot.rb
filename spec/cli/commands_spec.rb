# frozen_string_literal: true

require 'spec_helper'
require 'nanobot/cli/commands'
require 'tmpdir'

RSpec.describe Nanobot::CLI::Commands do
  let(:cli) { described_class.new }

  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  describe '#version' do
    it 'outputs the version string' do
      output = capture_stdout { cli.version }
      expect(output).to include("Nanobot version #{Nanobot::VERSION}")
    end
  end

  describe '#status' do
    context 'when config exists' do
      it 'outputs config path, workspace, model, and provider info' do
        config = Nanobot::Config::Config.new(
          providers: {
            anthropic: { api_key: 'test-key' },
            openai: { api_key: 'openai-key' }
          },
          provider: 'anthropic',
          agents: {
            defaults: {
              model: 'claude-haiku-4-5',
              workspace: '~/.nanobot/workspace'
            }
          }
        )
        config_path = Pathname.new('/tmp/test_config.json')

        allow(config_path).to receive(:exist?).and_return(true)
        allow(Nanobot::Config::Loader).to receive_messages(get_config_path: config_path, load: config)

        output = capture_stdout { cli.status }

        expect(output).to include('Configuration: /tmp/test_config.json')
        expect(output).to include('Workspace: ~/.nanobot/workspace')
        expect(output).to include('Model: claude-haiku-4-5')
        expect(output).to include('Anthropic: configured')
        expect(output).to include('OpenAI: configured')
        expect(output).to include('OpenRouter: not configured')
        expect(output).to include('Active provider: anthropic')
      end
    end

    context 'when config does not exist' do
      it 'says config not found' do
        config_path = Pathname.new('/nonexistent/config.json')

        allow(Nanobot::Config::Loader).to receive(:get_config_path).and_return(config_path)
        allow(config_path).to receive(:exist?).and_return(false)

        output = capture_stdout { cli.status }

        expect(output).to include("Configuration not found. Run 'nanobot onboard' first.")
      end
    end

    context 'when config has channels' do
      it 'outputs channel status' do
        config = Nanobot::Config::Config.new(
          providers: {
            anthropic: { api_key: 'test-key' }
          },
          provider: 'anthropic',
          agents: {
            defaults: {
              model: 'claude-haiku-4-5',
              workspace: '~/.nanobot/workspace'
            }
          },
          channels: {
            telegram: { enabled: true, token: 'tok' },
            discord: { enabled: false }
          }
        )
        config_path = Pathname.new('/tmp/test_config.json')

        allow(config_path).to receive(:exist?).and_return(true)
        allow(Nanobot::Config::Loader).to receive_messages(get_config_path: config_path, load: config)

        output = capture_stdout { cli.status }

        expect(output).to include('Channels:')
        expect(output).to include('Telegram: enabled')
        expect(output).to include('Discord: disabled')
        expect(output).to include('Gateway: disabled')
        expect(output).to include('Slack: disabled')
        expect(output).to include('Email: disabled')
      end
    end
  end

  describe '#onboard' do
    context 'when config does not exist' do
      it 'creates config and workspace' do
        Dir.mktmpdir do |tmpdir|
          config_path = Pathname.new(File.join(tmpdir, 'config.json'))
          workspace_path = File.join(tmpdir, 'workspace')

          config = Nanobot::Config::Config.new(
            agents: {
              defaults: {
                workspace: workspace_path
              }
            }
          )

          allow(Nanobot::Config::Loader).to receive_messages(get_config_path: config_path, create_default: config)

          output = capture_stdout { cli.onboard }

          expect(output).to include("Created configuration at #{config_path}")
          expect(output).to include("Created workspace at #{workspace_path}")
          expect(output).to include('Setup complete!')
          expect(Pathname.new(workspace_path)).to exist
          expect(Pathname.new(workspace_path) / 'memory').to exist
        end
      end
    end

    context 'when config already exists' do
      it 'prompts to overwrite and keeps existing config on decline' do
        Dir.mktmpdir do |tmpdir|
          config_path = Pathname.new(File.join(tmpdir, 'config.json'))
          FileUtils.touch(config_path)
          workspace_path = File.join(tmpdir, 'workspace')

          config = Nanobot::Config::Config.new(
            agents: {
              defaults: {
                workspace: workspace_path
              }
            }
          )

          allow(Nanobot::Config::Loader).to receive_messages(get_config_path: config_path, load: config)
          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout { cli.onboard }

          expect(output).to include("Configuration already exists at #{config_path}")
          expect(output).not_to include("Created configuration at #{config_path}")
          expect(output).to include('Setup complete!')
        end
      end

      it 'overwrites config when user confirms' do
        Dir.mktmpdir do |tmpdir|
          config_path = Pathname.new(File.join(tmpdir, 'config.json'))
          FileUtils.touch(config_path)
          workspace_path = File.join(tmpdir, 'workspace')

          config = Nanobot::Config::Config.new(
            agents: {
              defaults: {
                workspace: workspace_path
              }
            }
          )

          allow(Nanobot::Config::Loader).to receive_messages(get_config_path: config_path, load: config,
                                                             create_default: config)
          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout { cli.onboard }

          expect(output).to include("Configuration already exists at #{config_path}")
          expect(output).to include("Created configuration at #{config_path}")
          expect(output).to include('Setup complete!')
        end
      end
    end
  end

  describe '#serve' do
    context 'when workspace does not exist' do
      it 'tells user to run onboard first' do
        config = Nanobot::Config::Config.new(
          providers: {
            anthropic: { api_key: 'real-key-here' }
          },
          provider: 'anthropic',
          agents: {
            defaults: {
              workspace: '/nonexistent/workspace'
            }
          }
        )

        allow(Nanobot::Config::Loader).to receive_messages(exists?: true, load: config)

        output = capture_stdout do
          expect { cli.serve }.to raise_error(SystemExit)
        end

        expect(output).to include("Workspace not found. Run 'nanobot onboard' first.")
      end
    end
  end

  describe '#agent' do
    context 'when workspace does not exist' do
      it 'tells user to run onboard first' do
        config = Nanobot::Config::Config.new(
          providers: {
            anthropic: { api_key: 'real-key-here' }
          },
          provider: 'anthropic',
          agents: {
            defaults: {
              workspace: '/nonexistent/workspace'
            }
          }
        )

        allow(Nanobot::Config::Loader).to receive_messages(exists?: true, load: config)

        output = capture_stdout do
          expect { cli.agent }.to raise_error(SystemExit)
        end

        expect(output).to include("Workspace not found. Run 'nanobot onboard' first.")
      end
    end
  end
end
