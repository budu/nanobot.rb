# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot::Agent::MemoryStore do
  let(:workspace) { Dir.mktmpdir }
  let(:memory_store) { described_class.new(workspace) }
  let(:memory_dir) { Pathname.new(workspace) / 'memory' }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe '#initialize' do
    it 'initializes with workspace' do
      expect(memory_store.workspace.to_s).to eq(Pathname.new(workspace).expand_path.to_s)
    end

    it 'creates memory directory if not exists' do
      # Accessing memory_store triggers initialization
      expect(memory_store.instance_variable_get(:@memory_dir)).to be_directory
    end
  end

  describe '#read_long_term' do
    it 'returns nil if MEMORY.md does not exist' do
      expect(memory_store.read_long_term).to be_nil
    end

    it 'returns content if MEMORY.md exists' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / 'MEMORY.md').write('Long term memory content')

      expect(memory_store.read_long_term).to eq('Long term memory content')
    end
  end

  describe '#write_long_term' do
    it 'writes content to MEMORY.md' do
      memory_store.write_long_term('New memory content')

      expect((memory_dir / 'MEMORY.md').read).to eq('New memory content')
    end

    it 'overwrites existing content' do
      memory_store.write_long_term('First content')
      memory_store.write_long_term('Second content')

      expect((memory_dir / 'MEMORY.md').read).to eq('Second content')
    end
  end

  describe '#append_long_term' do
    it 'appends content to MEMORY.md' do
      memory_store.write_long_term('First content')
      memory_store.append_long_term('Second content')

      content = (memory_dir / 'MEMORY.md').read
      expect(content).to include('First content')
      expect(content).to include('Second content')
    end

    it 'creates file if not exists' do
      memory_store.append_long_term('New content')

      expect((memory_dir / 'MEMORY.md').read).to eq('New content')
    end

    it 'adds separator between contents' do
      memory_store.write_long_term('First')
      memory_store.append_long_term('Second')

      content = (memory_dir / 'MEMORY.md').read
      expect(content).to eq("First\n\nSecond")
    end

    it 'does not add separator for empty file' do
      memory_store.append_long_term('First')

      content = (memory_dir / 'MEMORY.md').read
      expect(content).to eq('First')
    end
  end

  describe '#read_today' do
    it 'returns nil if today\'s note does not exist' do
      expect(memory_store.read_today).to be_nil
    end

    it 'returns content of today\'s note' do
      memory_dir.mkpath unless memory_dir.exist?
      today_file = memory_dir / "#{Date.today.strftime('%Y-%m-%d')}.md"
      today_file.write('Today\'s content')

      expect(memory_store.read_today).to eq('Today\'s content')
    end
  end

  describe '#write_today' do
    it 'writes content to today\'s note' do
      memory_store.write_today('Today\'s content')

      today_file = memory_dir / "#{Date.today.strftime('%Y-%m-%d')}.md"
      expect(today_file.read).to eq('Today\'s content')
    end

    it 'overwrites existing content' do
      memory_store.write_today('First')
      memory_store.write_today('Second')

      today_file = memory_dir / "#{Date.today.strftime('%Y-%m-%d')}.md"
      expect(today_file.read).to eq('Second')
    end
  end

  describe '#append_today' do
    it 'appends content to today\'s note with timestamp' do
      memory_store.append_today('First entry')
      memory_store.append_today('Second entry')

      content = memory_store.read_today
      expect(content).to include('First entry')
      expect(content).to include('Second entry')
      expect(content).to match(/##\s+\d{2}:\d{2}:\d{2}/)
    end

    it 'creates file with header if not exists' do
      memory_store.append_today('New entry')

      content = memory_store.read_today
      expect(content).to include("# Daily Notes - #{Date.today}")
      expect(content).to include('New entry')
    end

    it 'can append without timestamp' do
      memory_store.append_today('Entry without timestamp', timestamp: false)

      content = memory_store.read_today
      expect(content).to include('Entry without timestamp')
      expect(content).not_to match(/##\s+\d{2}:\d{2}:\d{2}/)
    end

    it 'formats timestamp correctly when enabled' do
      Timecop.freeze(Time.new(2024, 1, 1, 14, 30, 45)) do
        memory_store.append_today('Test entry', timestamp: true)

        content = memory_store.read_today
        expect(content).to include('## 14:30:45')
      end
    end
  end

  describe '#get_memory_context' do
    it 'returns nil if no memory exists' do
      expect(memory_store.get_memory_context).to be_nil
    end

    it 'returns long-term memory only' do
      memory_store.write_long_term('Long term content')

      context = memory_store.get_memory_context(include_today: false)
      expect(context).to include('Long-term Memory')
      expect(context).to include('Long term content')
    end

    it 'returns both long-term and today\'s notes' do
      memory_store.write_long_term('Long term content')
      memory_store.write_today('Today\'s content')

      context = memory_store.get_memory_context
      expect(context).to include('Long-term Memory')
      expect(context).to include('Today\'s Notes')
      expect(context).to include('Long term content')
      expect(context).to include('Today\'s content')
    end

    it 'excludes today\'s notes when include_today is false' do
      memory_store.write_long_term('Long term content')
      memory_store.write_today('Today\'s content')

      context = memory_store.get_memory_context(include_today: false)
      expect(context).to include('Long term content')
      expect(context).not_to include('Today\'s Notes')
    end

    it 'separates sections with divider' do
      memory_store.write_long_term('Long term')
      memory_store.write_today('Today')

      context = memory_store.get_memory_context
      expect(context).to include('---')
    end

    it 'ignores empty long-term memory' do
      memory_store.write_long_term('')
      memory_store.write_today('Today\'s content')

      context = memory_store.get_memory_context
      expect(context).not_to include('Long-term Memory')
      expect(context).to include('Today\'s Notes')
    end

    it 'ignores whitespace-only long-term memory' do
      memory_store.write_long_term('   ')
      memory_store.write_today('Today\'s content')

      context = memory_store.get_memory_context
      expect(context).not_to include('Long-term Memory')
    end
  end

  describe '#list_daily_notes' do
    it 'returns empty array if no notes exist' do
      expect(memory_store.list_daily_notes).to eq([])
    end

    it 'lists all daily notes' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-01.md').write('Day 1')
      (memory_dir / '2024-01-02.md').write('Day 2')
      (memory_dir / '2024-01-03.md').write('Day 3')

      notes = memory_store.list_daily_notes
      expect(notes.length).to eq(3)
    end

    it 'returns notes sorted by date descending' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-01.md').write('Day 1')
      (memory_dir / '2024-01-03.md').write('Day 3')
      (memory_dir / '2024-01-02.md').write('Day 2')

      notes = memory_store.list_daily_notes
      expect(notes[0][:date]).to eq(Date.new(2024, 1, 3))
      expect(notes[1][:date]).to eq(Date.new(2024, 1, 2))
      expect(notes[2][:date]).to eq(Date.new(2024, 1, 1))
    end

    it 'includes date and path in results' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-01.md').write('Content')

      notes = memory_store.list_daily_notes
      expect(notes.first[:date]).to be_a(Date)
      expect(notes.first[:path]).to be_a(Pathname)
    end

    it 'ignores non-date files' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-01.md').write('Valid')
      (memory_dir / 'MEMORY.md').write('Not a daily note')
      (memory_dir / 'notes.txt').write('Not a daily note')

      notes = memory_store.list_daily_notes
      expect(notes.length).to eq(1)
    end
  end

  describe '#read_daily_note' do
    it 'reads note by Date object' do
      memory_dir.mkpath unless memory_dir.exist?
      date = Date.new(2024, 1, 15)
      (memory_dir / '2024-01-15.md').write('Content for Jan 15')

      content = memory_store.read_daily_note(date)
      expect(content).to eq('Content for Jan 15')
    end

    it 'reads note by date string' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-15.md').write('Content')

      content = memory_store.read_daily_note('2024-01-15')
      expect(content).to eq('Content')
    end

    it 'returns nil if note does not exist' do
      content = memory_store.read_daily_note(Date.new(2024, 1, 15))
      expect(content).to be_nil
    end

    it 'handles various date string formats' do
      memory_dir.mkpath unless memory_dir.exist?
      (memory_dir / '2024-01-15.md').write('Content')

      content = memory_store.read_daily_note('2024-1-15')
      expect(content).to eq('Content')
    end
  end

  describe 'private methods' do
    describe '#today_file' do
      it 'returns correct path for today' do
        today_file = memory_store.send(:today_file)
        expected_name = "#{Date.today.strftime('%Y-%m-%d')}.md"

        expect(today_file.basename.to_s).to eq(expected_name)
      end
    end
  end

  describe 'integration scenarios' do
    it 'manages memory across multiple days' do
      memory_dir.mkpath unless memory_dir.exist?
      # Simulate multiple days
      Timecop.freeze(Date.new(2024, 1, 1)) do
        memory_store.append_today('Day 1 entry')
      end

      Timecop.freeze(Date.new(2024, 1, 2)) do
        memory_store.append_today('Day 2 entry')
      end

      Timecop.freeze(Date.new(2024, 1, 3)) do
        memory_store.append_today('Day 3 entry')
      end

      notes = memory_store.list_daily_notes
      expect(notes.length).to eq(3)

      content1 = memory_store.read_daily_note('2024-01-01')
      expect(content1).to include('Day 1 entry')

      content2 = memory_store.read_daily_note('2024-01-02')
      expect(content2).to include('Day 2 entry')
    end

    it 'combines long-term memory with daily notes' do
      memory_dir.mkpath unless memory_dir.exist?
      memory_store.write_long_term('Important long-term information')

      Timecop.freeze(Date.new(2024, 1, 1)) do
        memory_store.append_today('Today\'s task list')
      end

      # Get context on same day to include today's notes
      context = nil
      Timecop.freeze(Date.new(2024, 1, 1)) do
        context = memory_store.get_memory_context
      end

      expect(context).to include('Important long-term information')
      expect(context).to include('Today\'s task list')
    end
  end
end
