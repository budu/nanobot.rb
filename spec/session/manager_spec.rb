# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Session::Manager do
  let(:workspace) { Dir.mktmpdir }
  let(:manager) { described_class.new(workspace) }

  after do
    FileUtils.rm_rf(workspace)
    # Clean up test sessions
    sessions_dir = Pathname.new(File.expand_path('~/.nanobot/sessions'))
    sessions_dir.glob('*.jsonl').each(&:delete) if sessions_dir.exist?
  end

  describe '#initialize' do
    it 'initializes with workspace' do
      expect(manager.workspace.to_s).to eq(Pathname.new(workspace).expand_path.to_s)
    end

    it 'creates sessions directory if not exists' do
      expect(manager.sessions_dir).to be_directory
    end

    it 'starts with empty cache' do
      expect(manager.cache_size).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'creates new session if not exists' do
      session = manager.get_or_create('test:chat1')

      expect(session).to be_a(Nanobot::Session::Session)
      expect(session.key).to eq('test:chat1')
      expect(session.message_count).to eq(0)
    end

    it 'returns cached session if exists' do
      session1 = manager.get_or_create('test:chat1')
      session1.add_message('user', 'Hello')

      session2 = manager.get_or_create('test:chat1')
      expect(session2).to eq(session1)
      expect(session2.message_count).to eq(1)
    end

    it 'loads session from disk if exists' do
      session = manager.get_or_create('test:chat1')
      session.add_message('user', 'Hello')
      manager.save(session)

      # Create new manager to test loading
      manager2 = described_class.new(workspace)
      loaded_session = manager2.get_or_create('test:chat1')

      expect(loaded_session.message_count).to eq(1)
      expect(loaded_session.messages.first[:content]).to eq('Hello')
    end
  end

  describe '#save' do
    it 'saves session to disk' do
      session = manager.get_or_create('test:chat1')
      session.add_message('user', 'Hello')
      session.add_message('assistant', 'Hi there')

      manager.save(session)

      path = manager.sessions_dir / 'test%3Achat1.jsonl'
      expect(path).to exist
    end

    it 'updates cache' do
      session = manager.get_or_create('test:chat1')
      manager.save(session)

      expect(manager.cache_size).to eq(1)
    end

    it 'saves metadata correctly' do
      session = manager.get_or_create('test:chat1')
      session.metadata = { user: 'test_user' }
      manager.save(session)

      manager2 = described_class.new(workspace)
      loaded = manager2.get_or_create('test:chat1')
      expect(loaded.metadata).to eq(user: 'test_user')
    end

    it 'saves timestamps correctly' do
      session = manager.get_or_create('test:chat1')
      created_time = session.created_at
      manager.save(session)

      manager2 = described_class.new(workspace)
      loaded = manager2.get_or_create('test:chat1')
      expect(loaded.created_at.to_i).to eq(created_time.to_i)
    end
  end

  describe '#delete' do
    it 'deletes existing session' do
      session = manager.get_or_create('test:chat1')
      manager.save(session)

      result = manager.delete('test:chat1')
      expect(result).to be true

      path = manager.sessions_dir / 'test%3Achat1.jsonl'
      expect(path).not_to exist
    end

    it 'returns false if session does not exist' do
      result = manager.delete('nonexistent')
      expect(result).to be false
    end

    it 'removes session from cache' do
      session = manager.get_or_create('test:chat1')
      manager.save(session)

      expect(manager.cache_size).to eq(1)

      manager.delete('test:chat1')
      expect(manager.cache_size).to eq(0)
    end
  end

  describe '#list_sessions' do
    it 'lists all sessions' do
      session1 = manager.get_or_create('test:chat1')
      session2 = manager.get_or_create('test:chat2')

      manager.save(session1)
      manager.save(session2)

      sessions = manager.list_sessions
      expect(sessions.length).to eq(2)
    end

    it 'returns sessions sorted by updated_at' do
      session1 = manager.get_or_create('test:chat1')
      manager.save(session1)

      sleep 0.01

      session2 = manager.get_or_create('test:chat2')
      manager.save(session2)

      sessions = manager.list_sessions
      expect(sessions.first[:key]).to eq('test:chat2')
    end

    it 'returns empty array if no sessions' do
      sessions = manager.list_sessions
      expect(sessions).to eq([])
    end

    it 'includes session metadata in listing' do
      session = manager.get_or_create('test:chat1')
      manager.save(session)

      sessions = manager.list_sessions
      expect(sessions.first).to have_key(:created_at)
      expect(sessions.first).to have_key(:updated_at)
      expect(sessions.first).to have_key(:path)
    end
  end

  describe '#clear_cache' do
    it 'clears all cached sessions' do
      manager.get_or_create('test:chat1')
      manager.get_or_create('test:chat2')

      expect(manager.cache_size).to eq(2)

      manager.clear_cache
      expect(manager.cache_size).to eq(0)
    end
  end

  describe '#cache_size' do
    it 'returns number of cached sessions' do
      expect(manager.cache_size).to eq(0)

      manager.get_or_create('test:chat1')
      expect(manager.cache_size).to eq(1)

      manager.get_or_create('test:chat2')
      expect(manager.cache_size).to eq(2)
    end
  end

  describe 'private methods' do
    describe '#load' do
      it 'handles corrupted session files gracefully' do
        path = manager.sessions_dir / 'corrupted.jsonl'
        path.write('invalid json')

        # Should not raise error
        session = manager.get_or_create('corrupted')
        expect(session).to be_a(Nanobot::Session::Session)
        expect(session.message_count).to eq(0)
      end

      it 'handles empty session files' do
        path = manager.sessions_dir / 'empty.jsonl'
        path.write('')

        session = manager.get_or_create('empty')
        expect(session).to be_a(Nanobot::Session::Session)
      end
    end

    describe '#safe_filename' do
      it 'percent-encodes special characters' do
        session = manager.get_or_create('test:chat@#$%')
        manager.save(session)

        # Check that the file exists with percent-encoded name
        path = manager.sessions_dir / 'test%3Achat%40%23%24%25.jsonl'
        expect(path).to exist
      end
    end
  end
end

RSpec.describe Nanobot::Session::Session do
  let(:session) { described_class.new('test:chat1') }

  describe '#initialize' do
    it 'initializes with key' do
      expect(session.key).to eq('test:chat1')
    end

    it 'starts with empty messages' do
      expect(session.messages).to eq([])
    end

    it 'sets created_at and updated_at' do
      expect(session.created_at).to be_a(Time)
      expect(session.updated_at).to be_a(Time)
    end

    it 'accepts optional parameters' do
      messages = [{ role: 'user', content: 'Hello' }]
      metadata = { user: 'test' }
      created = Time.now - 3600
      updated = Time.now - 1800

      session = described_class.new(
        'test:chat2',
        messages: messages,
        created_at: created,
        updated_at: updated,
        metadata: metadata
      )

      expect(session.messages).to eq(messages)
      expect(session.metadata).to eq(metadata)
      expect(session.created_at).to eq(created)
      expect(session.updated_at).to eq(updated)
    end
  end

  describe '#add_message' do
    it 'adds message with role and content' do
      session.add_message('user', 'Hello')

      expect(session.messages.length).to eq(1)
      expect(session.messages.first[:role]).to eq('user')
      expect(session.messages.first[:content]).to eq('Hello')
    end

    it 'adds timestamp to message' do
      session.add_message('user', 'Hello')

      expect(session.messages.first[:timestamp]).to be_a(String)
    end

    it 'updates updated_at timestamp' do
      old_time = session.updated_at
      sleep 0.01
      session.add_message('user', 'Hello')

      expect(session.updated_at).to be > old_time
    end

    it 'includes tool_calls when provided' do
      tool_calls = [{ id: 'call_1', name: 'test' }]
      session.add_message('assistant', 'Using tool', tool_calls: tool_calls)

      expect(session.messages.first[:tool_calls]).to eq(tool_calls)
    end

    it 'does not include tool_calls when nil' do
      session.add_message('user', 'Hello')

      expect(session.messages.first).not_to have_key(:tool_calls)
    end
  end

  describe '#get_history' do
    it 'returns all messages in LLM format' do
      session.add_message('user', 'Hello')
      session.add_message('assistant', 'Hi')

      history = session.get_history

      expect(history.length).to eq(2)
      expect(history.first[:role]).to eq('user')
      expect(history.first[:content]).to eq('Hello')
    end

    it 'limits to max_messages' do
      10.times { |i| session.add_message('user', "Message #{i}") }

      history = session.get_history(max_messages: 5)
      expect(history.length).to eq(5)
    end

    it 'returns most recent messages when limiting' do
      10.times { |i| session.add_message('user', "Message #{i}") }

      history = session.get_history(max_messages: 5)
      expect(history.last[:content]).to eq('Message 9')
    end

    it 'excludes timestamp from LLM format' do
      session.add_message('user', 'Hello')

      history = session.get_history
      expect(history.first).not_to have_key(:timestamp)
    end

    it 'includes tool_calls when present' do
      tool_calls = [{ id: 'call_1', name: 'test' }]
      session.add_message('assistant', 'Using tool', tool_calls: tool_calls)

      history = session.get_history
      expect(history.first[:tool_calls]).to eq(tool_calls)
    end
  end

  describe '#clear' do
    it 'removes all messages' do
      session.add_message('user', 'Hello')
      session.add_message('assistant', 'Hi')

      session.clear

      expect(session.messages).to eq([])
    end

    it 'updates updated_at timestamp' do
      old_time = session.updated_at
      sleep 0.01
      session.clear

      expect(session.updated_at).to be > old_time
    end
  end

  describe '#message_count' do
    it 'returns number of messages' do
      expect(session.message_count).to eq(0)

      session.add_message('user', 'Hello')
      expect(session.message_count).to eq(1)

      session.add_message('assistant', 'Hi')
      expect(session.message_count).to eq(2)
    end
  end
end
