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
        expect(output).not_to include('OpenRouter')
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

    context 'when workspace exists' do
      it 'starts manager, registers channels, and runs agent loop' do
        Dir.mktmpdir do |tmpdir|
          config = Nanobot::Config::Config.new(
            providers: { anthropic: { api_key: 'real-key-here' } },
            provider: 'anthropic',
            agents: { defaults: { workspace: tmpdir } }
          )

          agent_loop = instance_double(Nanobot::Agent::Loop, run: nil, stop: nil)
          manager = instance_double(Nanobot::Channels::Manager, start_all: nil, stop_all: nil)

          allow(Nanobot::Config::Loader).to receive_messages(exists?: true, load: config)
          allow(Nanobot::Agent::Loop).to receive(:new).and_return(agent_loop)
          allow(Nanobot::Channels::Manager).to receive(:new).and_return(manager)

          output = capture_stdout { cli.serve }

          expect(output).to include('Nanobot service started')
          expect(manager).to have_received(:start_all)
          expect(agent_loop).to have_received(:run)
        end
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

    context 'when workspace exists' do
      let(:tmpdir) { Dir.mktmpdir }
      let(:agent_loop) { instance_double(Nanobot::Agent::Loop) }

      before do
        config = Nanobot::Config::Config.new(
          providers: { anthropic: { api_key: 'real-key-here' } },
          provider: 'anthropic',
          agents: { defaults: { workspace: tmpdir } }
        )
        allow(Nanobot::Config::Loader).to receive_messages(exists?: true, load: config)
        allow(Nanobot::Agent::Loop).to receive(:new).and_return(agent_loop)
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'runs single message mode with -m flag' do
        allow(agent_loop).to receive(:process_direct).and_return('Hello back!')

        cli_with_msg = described_class.new([], { message: 'Hello' })

        output = capture_stdout { cli_with_msg.agent }

        expect(output).to include('Processing message...')
        expect(output).to include('Hello back!')
        expect(agent_loop).to have_received(:process_direct).with('Hello')
      end

      it 'runs interactive mode without -m flag' do
        allow($stdin).to receive(:gets).and_return("hello\n", "exit\n")
        allow(agent_loop).to receive(:process_direct).and_return('Hi!')

        output = capture_stdout { cli.agent }

        expect(output).to include('Nanobot Agent (interactive mode)')
        expect(output).to include('Goodbye!')
        expect(agent_loop).to have_received(:process_direct).with('hello')
      end

      it 'handles errors in interactive mode' do
        allow($stdin).to receive(:gets).and_return("test\n", "exit\n")
        allow(agent_loop).to receive(:process_direct).and_raise(StandardError, 'something broke')

        output = capture_stdout { cli.agent }

        expect(output).to include('Error: something broke')
      end

      it 'exits interactive mode on nil input (EOF)' do
        allow($stdin).to receive(:gets).and_return(nil)
        allow(agent_loop).to receive(:process_direct)

        output = capture_stdout { cli.agent }

        expect(output).to include('Goodbye!')
      end

      it 'skips empty input in interactive mode' do
        allow($stdin).to receive(:gets).and_return("  \n", "quit\n")
        allow(agent_loop).to receive(:process_direct)

        capture_stdout { cli.agent }

        expect(agent_loop).not_to have_received(:process_direct)
      end
    end
  end

  describe 'private helpers' do
    describe '#create_logger' do
      it 'sets debug level when debug flag is true' do
        config = Nanobot::Config::Config.new
        result = cli.send(:create_logger, config, true)
        expect(result.level).to eq(Logger::DEBUG)
      end

      it 'sets level from config string' do
        config = Nanobot::Config::Config.new(agents: { defaults: { log_level: 'warn' } })
        result = cli.send(:create_logger, config, false)
        expect(result.level).to eq(Logger::WARN)
      end

      it 'sets error level from config' do
        config = Nanobot::Config::Config.new(agents: { defaults: { log_level: 'error' } })
        result = cli.send(:create_logger, config, false)
        expect(result.level).to eq(Logger::ERROR)
      end

      it 'defaults to info level' do
        config = Nanobot::Config::Config.new(agents: { defaults: { log_level: 'info' } })
        result = cli.send(:create_logger, config, false)
        expect(result.level).to eq(Logger::INFO)
      end

      it 'formats log messages with severity prefix' do
        config = Nanobot::Config::Config.new
        result = cli.send(:create_logger, config, false)
        formatted = result.formatter.call('INFO', Time.now, nil, 'test message')
        expect(formatted).to eq("INFO: test message\n")
      end
    end

    describe '#create_provider' do
      it 'exits when no API key configured' do
        config = Nanobot::Config::Config.new(
          providers: { anthropic: {} },
          provider: 'anthropic'
        )

        output = capture_stdout do
          expect { cli.send(:create_provider, config) }.to raise_error(SystemExit)
        end

        expect(output).to include('No API key configured')
      end

      it 'exits when placeholder API key detected' do
        config = Nanobot::Config::Config.new(
          providers: { anthropic: { api_key: 'sk-ant-api03-...' } },
          provider: 'anthropic'
        )

        output = capture_stdout do
          expect { cli.send(:create_provider, config) }.to raise_error(SystemExit)
        end

        expect(output).to include('Placeholder API key detected')
      end
    end

    describe '#load_config' do
      it 'exits when config does not exist' do
        allow(Nanobot::Config::Loader).to receive(:exists?).and_return(false)

        output = capture_stdout do
          expect { cli.send(:load_config) }.to raise_error(SystemExit)
        end

        expect(output).to include("Configuration not found. Run 'nanobot onboard' first.")
      end
    end

    describe '#register_channels' do
      it 'registers enabled channels' do
        config = Nanobot::Config::Config.new(
          channels: { telegram: { enabled: true, token: 'tok' } }
        )
        bus = instance_double(Nanobot::Bus::MessageBus)
        logger = test_logger
        manager = instance_double(Nanobot::Channels::Manager)
        allow(manager).to receive(:add_channel)

        cli.send(:register_channels, manager, config, bus, logger)

        expect(manager).to have_received(:add_channel).once
      end

      it 'skips disabled channels' do
        config = Nanobot::Config::Config.new(
          channels: { telegram: { enabled: false } }
        )
        bus = instance_double(Nanobot::Bus::MessageBus)
        logger = test_logger
        manager = instance_double(Nanobot::Channels::Manager)
        allow(manager).to receive(:add_channel)

        cli.send(:register_channels, manager, config, bus, logger)

        expect(manager).not_to have_received(:add_channel)
      end

      it 'handles LoadError for missing channel gems' do
        config = Nanobot::Config::Config.new(
          channels: { email: { enabled: true } }
        )
        bus = instance_double(Nanobot::Bus::MessageBus)
        logger = test_logger
        manager = instance_double(Nanobot::Channels::Manager)
        allow(manager).to receive(:add_channel)
        allow(logger).to receive(:error)

        # Email requires net/imap which should be available, so we force LoadError
        allow(cli).to receive(:require_relative).and_call_original
        allow(cli).to receive(:require_relative).with('../channels/email').and_raise(LoadError, 'cannot load email')

        cli.send(:register_channels, manager, config, bus, logger)

        expect(logger).to have_received(:error).with(match(/Failed to load email channel/))
      end
    end

    describe '#setup_signal_traps' do
      it 'sets up INT and TERM signal traps' do
        manager = instance_double(Nanobot::Channels::Manager)
        agent_loop = instance_double(Nanobot::Agent::Loop)
        logger = test_logger
        allow(logger).to receive(:info)

        traps = {}
        allow(cli).to receive(:trap) { |signal, &block| traps[signal] = block }

        cli.send(:setup_signal_traps, manager, agent_loop, logger)

        expect(traps).to have_key('INT')
        expect(traps).to have_key('TERM')
      end
    end
  end
end
