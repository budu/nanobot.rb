# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Config::Loader do
  let(:temp_config_path) { File.join(Dir.mktmpdir, 'test_config.json') }

  after do
    FileUtils.rm_f(temp_config_path)
  end

  describe '.load' do
    context 'when config file does not exist' do
      it 'returns default config' do
        config = described_class.load('/nonexistent/config.json')
        expect(config).to be_a(Nanobot::Config::Config)
      end
    end

    context 'when config file exists' do
      it 'loads config from file' do
        config_data = {
          agents: {
            defaults: {
              model: 'gpt-4o',
              workspace: '/custom/workspace'
            }
          }
        }
        File.write(temp_config_path, JSON.pretty_generate(config_data))

        config = described_class.load(temp_config_path)
        expect(config.agents.defaults.model).to eq('gpt-4o')
        expect(config.agents.defaults.workspace).to eq('/custom/workspace')
      end

      it 'raises error on invalid JSON' do
        File.write(temp_config_path, 'invalid json')

        expect do
          described_class.load(temp_config_path)
        end.to raise_error(/Error loading config/)
      end
    end

    it 'uses default path when none provided' do
      config = described_class.load
      expect(config).to be_a(Nanobot::Config::Config)
    end
  end

  describe '.save' do
    it 'saves config to file' do
      config = Nanobot::Config::Config.new
      described_class.save(config, temp_config_path)

      expect(File).to exist(temp_config_path)
    end

    it 'creates directory if not exists' do
      nested_path = File.join(Dir.mktmpdir, 'nested', 'dir', 'config.json')
      config = Nanobot::Config::Config.new

      described_class.save(config, nested_path)
      expect(File).to exist(nested_path)

      FileUtils.rm_rf(File.dirname(nested_path, 2))
    end

    it 'saves as pretty JSON' do
      config = Nanobot::Config::Config.new
      described_class.save(config, temp_config_path)

      content = File.read(temp_config_path)
      expect(content).to include("\n")
      expect { JSON.parse(content) }.not_to raise_error
    end

    it 'preserves config data' do
      # Create config with custom model
      config = Nanobot::Config::Config.new(
        agents: {
          defaults: {
            model: 'custom-model'
          }
        }
      )

      described_class.save(config, temp_config_path)
      loaded = described_class.load(temp_config_path)

      expect(loaded.agents.defaults.model).to eq('custom-model')
    end
  end

  describe '.get_config_path' do
    it 'returns default path when none provided' do
      path = described_class.get_config_path
      expect(path.to_s).to eq(File.expand_path('~/.nanobot/config.json'))
    end

    it 'returns custom path when provided' do
      path = described_class.get_config_path('/custom/config.json')
      expect(path.to_s).to eq('/custom/config.json')
    end
  end

  describe '.exists?' do
    it 'returns false when config does not exist' do
      expect(described_class.exists?('/nonexistent/config.json')).to be false
    end

    it 'returns true when config exists' do
      FileUtils.touch(temp_config_path)
      expect(described_class.exists?(temp_config_path)).to be true
    end
  end

  describe '.create_default' do
    it 'creates default config file' do
      config = described_class.create_default(temp_config_path)

      expect(File).to exist(temp_config_path)
      expect(config).to be_a(Nanobot::Config::Config)
    end

    it 'returns default config' do
      config = described_class.create_default(temp_config_path)

      expect(config.agents.defaults.model).to eq('claude-haiku-4-5')
      expect(config.provider).to eq('anthropic')
    end
  end

  describe 'private methods' do
    describe '.config_to_hash' do
      it 'converts config to hash' do
        config = Nanobot::Config::Config.new(
          agents: {
            defaults: {
              model: 'test-model',
              workspace: '/test'
            }
          }
        )

        hash = described_class.send(:config_to_hash, config)
        expect(hash).to be_a(Hash)
        expect(hash[:agents][:defaults][:model]).to eq('test-model')
      end

      it 'excludes nil values' do
        config = Nanobot::Config::Config.new
        hash = described_class.send(:config_to_hash, config)

        # Providers with nil values should not have empty hashes
        expect(hash[:providers]).to be_a(Hash)
      end
    end

    describe '.providers_to_hash' do
      it 'converts providers config' do
        providers = Nanobot::Config::ProvidersConfig.new(
          openai: { api_key: 'test-key' }
        )

        hash = described_class.send(:providers_to_hash, providers)
        expect(hash[:openai][:api_key]).to eq('test-key')
      end

      it 'excludes nil providers' do
        providers = Nanobot::Config::ProvidersConfig.new
        hash = described_class.send(:providers_to_hash, providers)
        expect(hash).to eq({})
      end
    end

    describe '.agents_to_hash' do
      it 'converts agents config' do
        agents = Nanobot::Config::AgentsConfig.new(
          defaults: { model: 'test-model' }
        )

        hash = described_class.send(:agents_to_hash, agents)
        expect(hash[:defaults][:model]).to eq('test-model')
      end
    end

    describe '.tools_to_hash' do
      it 'converts tools config' do
        tools = Nanobot::Config::ToolsConfig.new(
          exec: { timeout: 120 },
          restrict_to_workspace: true
        )

        hash = described_class.send(:tools_to_hash, tools)
        expect(hash[:exec][:timeout]).to eq(120)
        expect(hash[:restrict_to_workspace]).to be true
      end
    end
  end
end
