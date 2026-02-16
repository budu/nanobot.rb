# frozen_string_literal: true

require 'spec_helper'
require 'mail'
require 'nanobot/channels/email'

RSpec.describe Nanobot::Channels::Email do
  let(:config) do
    Nanobot::Config::EmailConfig.new(
      enabled: true,
      consent_granted: true,
      imap_host: 'imap.example.com',
      imap_port: 993,
      imap_username: 'bot@example.com',
      imap_password: 'imap-secret',
      imap_mailbox: 'INBOX',
      imap_use_ssl: true,
      smtp_host: 'smtp.example.com',
      smtp_port: 587,
      smtp_username: 'bot@example.com',
      smtp_password: 'smtp-secret',
      smtp_use_tls: true,
      smtp_use_ssl: false,
      from_address: 'bot@example.com',
      auto_reply_enabled: true,
      poll_interval_seconds: 30,
      mark_seen: true,
      max_body_chars: 12_000,
      subject_prefix: 'Re: ',
      allow_from: []
    )
  end

  let(:bus) { instance_double(Nanobot::Bus::MessageBus) }
  let(:logger) { test_logger }

  let(:channel) do
    described_class.new(
      name: 'email',
      config: config,
      bus: bus,
      logger: logger
    )
  end

  # Test subclass that exposes private methods for unit testing
  let(:test_channel_class) do
    Class.new(described_class) do
      public :valid_config?, :extract_body, :html_to_text, :reply_subject, :fetch_new_messages
      attr_reader :processed_uids, :last_subject_by_chat, :last_message_id_by_chat
    end
  end

  let(:test_channel) do
    ch = test_channel_class.new(name: 'email', config: config, bus: bus, logger: logger)
    ch.instance_variable_set(:@processed_uids, Set.new)
    ch.instance_variable_set(:@last_subject_by_chat, {})
    ch.instance_variable_set(:@last_message_id_by_chat, {})
    ch
  end

  describe '#initialize' do
    it 'initializes with required parameters' do
      expect(channel.name).to eq('email')
      expect(channel.config).to eq(config)
      expect(channel.bus).to eq(bus)
    end

    it 'starts in not running state' do
      expect(channel.running?).to be false
    end
  end

  describe '#start' do
    context 'when consent_granted is false' do
      let(:config) do
        Nanobot::Config::EmailConfig.new(
          consent_granted: false,
          imap_host: 'imap.example.com',
          imap_username: 'bot@example.com',
          imap_password: 'secret',
          smtp_host: 'smtp.example.com',
          smtp_username: 'bot@example.com',
          smtp_password: 'secret'
        )
      end

      it 'does not start and logs a warning' do
        allow(logger).to receive(:warn)

        channel.start

        expect(channel.running?).to be false
        expect(logger).to have_received(:warn).with(/consent_granted is false/)
      end
    end

    context 'with missing config' do
      let(:config) do
        Nanobot::Config::EmailConfig.new(
          consent_granted: true,
          imap_host: nil,
          imap_username: nil,
          imap_password: nil,
          smtp_host: nil,
          smtp_username: nil,
          smtp_password: nil
        )
      end

      it 'does not start and logs an error' do
        allow(logger).to receive(:error)

        channel.start

        expect(channel.running?).to be false
        expect(logger).to have_received(:error)
          .with(/missing: imap_host, imap_username, imap_password, smtp_host, smtp_username, smtp_password/)
      end
    end

    context 'with valid config' do
      it 'enforces minimum poll interval of 5 seconds' do
        low_poll_config = Nanobot::Config::EmailConfig.new(
          consent_granted: true,
          imap_host: 'imap.example.com',
          imap_username: 'bot@example.com',
          imap_password: 'secret',
          smtp_host: 'smtp.example.com',
          smtp_username: 'bot@example.com',
          smtp_password: 'secret',
          poll_interval_seconds: 1
        )
        ch = described_class.new(name: 'email', config: low_poll_config, bus: bus, logger: logger)

        allow(logger).to receive(:info)
        allow(ch).to receive(:sleep) # prevent actual sleep
        allow(ch).to receive(:fetch_new_messages).and_return([])

        # Run start in a thread and stop it after one iteration
        t = Thread.new { ch.start }
        sleep 0.05
        ch.stop
        t.join(1)

        expect(logger).to have_received(:info).with(/polling every 5s/)
      end
    end
  end

  describe '#stop' do
    it 'sets running to false' do
      channel.instance_variable_set(:@running, true)
      channel.stop
      expect(channel.running?).to be false
    end
  end

  describe '#send' do
    let(:message) do
      Nanobot::Bus::OutboundMessage.new(
        channel: 'email',
        chat_id: 'user@example.com',
        content: 'Hello from bot'
      )
    end

    before do
      channel.instance_variable_set(:@last_subject_by_chat, {})
      channel.instance_variable_set(:@last_message_id_by_chat, {})
    end

    context 'when consent_granted is false' do
      let(:config) do
        Nanobot::Config::EmailConfig.new(consent_granted: false)
      end

      it 'does not send and logs a warning' do
        allow(logger).to receive(:warn)

        channel.send(message)

        expect(logger).to have_received(:warn).with(/consent_granted is false/)
      end
    end

    context 'when auto_reply_enabled is false' do
      let(:config) do
        Nanobot::Config::EmailConfig.new(
          consent_granted: true,
          auto_reply_enabled: false,
          smtp_host: 'smtp.example.com',
          smtp_username: 'bot@example.com',
          smtp_password: 'secret'
        )
      end

      it 'does not send and logs info' do
        allow(logger).to receive(:info)

        channel.send(message)

        expect(logger).to have_received(:info).with(/auto_reply_enabled is false/)
      end

      it 'sends when force_send metadata is set' do
        forced_message = Nanobot::Bus::OutboundMessage.new(
          channel: 'email',
          chat_id: 'user@example.com',
          content: 'Forced reply',
          metadata: { 'force_send' => true }
        )

        mail_double = double('mail_message')
        allow(Mail).to receive(:new).and_return(mail_double)
        allow(mail_double).to receive(:to=)
        allow(mail_double).to receive(:subject=)
        allow(mail_double).to receive(:body=)
        allow(mail_double).to receive(:from=)
        allow(mail_double).to receive(:delivery_method)
        allow(mail_double).to receive(:deliver)
        allow(mail_double).to receive(:[]=)

        channel.instance_variable_set(:@last_subject_by_chat, {})
        channel.instance_variable_set(:@last_message_id_by_chat, {})
        channel.send(forced_message)

        expect(mail_double).to have_received(:deliver)
      end
    end

    context 'when sending a reply' do
      it 'sends email via SMTP with correct fields' do
        mail_double = double('mail_message')
        allow(Mail).to receive(:new).and_return(mail_double)
        allow(mail_double).to receive(:to=)
        allow(mail_double).to receive(:subject=)
        allow(mail_double).to receive(:body=)
        allow(mail_double).to receive(:from=)
        allow(mail_double).to receive(:delivery_method)
        allow(mail_double).to receive(:deliver)

        channel.send(message)

        expect(mail_double).to have_received(:from=).with('bot@example.com')
        expect(mail_double).to have_received(:to=).with('user@example.com')
        expect(mail_double).to have_received(:delivery_method).with(:smtp, hash_including(
                                                                             address: 'smtp.example.com',
                                                                             port: 587,
                                                                             user_name: 'bot@example.com',
                                                                             password: 'smtp-secret'
                                                                           ))
        expect(mail_double).to have_received(:deliver)
      end

      it 'includes threading headers when previous message_id exists' do
        channel.instance_variable_set(
          :@last_message_id_by_chat,
          { 'user@example.com' => '<abc123@example.com>' }
        )

        mail_double = double('mail_message')
        allow(Mail).to receive(:new).and_return(mail_double)
        allow(mail_double).to receive(:to=)
        allow(mail_double).to receive(:subject=)
        allow(mail_double).to receive(:body=)
        allow(mail_double).to receive(:from=)
        allow(mail_double).to receive(:delivery_method)
        allow(mail_double).to receive(:deliver)
        allow(mail_double).to receive(:[]=)

        channel.send(message)

        expect(mail_double).to have_received(:[]=).with('In-Reply-To', '<abc123@example.com>')
        expect(mail_double).to have_received(:[]=).with('References', '<abc123@example.com>')
      end

      it 'does not include threading headers when no previous message_id' do
        mail_double = double('mail_message')
        allow(Mail).to receive(:new).and_return(mail_double)
        allow(mail_double).to receive(:to=)
        allow(mail_double).to receive(:subject=)
        allow(mail_double).to receive(:body=)
        allow(mail_double).to receive(:from=)
        allow(mail_double).to receive(:delivery_method)
        allow(mail_double).to receive(:deliver)
        allow(mail_double).to receive(:[]=)

        channel.send(message)

        expect(mail_double).not_to have_received(:[]=)
      end

      it 'uses last subject for reply subject' do
        channel.instance_variable_set(
          :@last_subject_by_chat,
          { 'user@example.com' => 'Help needed' }
        )

        mail_double = double('mail_message')
        allow(Mail).to receive(:new).and_return(mail_double)
        allow(mail_double).to receive(:to=)
        allow(mail_double).to receive(:subject=)
        allow(mail_double).to receive(:body=)
        allow(mail_double).to receive(:from=)
        allow(mail_double).to receive(:delivery_method)
        allow(mail_double).to receive(:deliver)

        channel.send(message)

        expect(mail_double).to have_received(:subject=).with('Re: Help needed')
      end

      it 'skips send when chat_id is empty' do
        empty_msg = Nanobot::Bus::OutboundMessage.new(
          channel: 'email',
          chat_id: '  ',
          content: 'Hello'
        )

        allow(Mail).to receive(:new)
        channel.send(empty_msg)
        expect(Mail).not_to have_received(:new)
      end
    end
  end

  describe '#valid_config?' do
    it 'returns true with all required fields' do
      expect(test_channel.valid_config?).to be true
    end

    it 'returns false and logs missing fields' do
      incomplete_config = Nanobot::Config::EmailConfig.new(
        consent_granted: true,
        imap_host: 'imap.example.com',
        imap_username: nil,
        imap_password: nil,
        smtp_host: nil,
        smtp_username: nil,
        smtp_password: nil
      )
      ch = test_channel_class.new(name: 'email', config: incomplete_config, bus: bus, logger: logger)
      allow(logger).to receive(:error)

      expect(ch.valid_config?).to be false
      expect(logger).to have_received(:error)
        .with(/missing: imap_username, imap_password, smtp_host, smtp_username, smtp_password/)
    end
  end

  describe '#extract_body' do
    it 'extracts plain text body' do
      mail = Mail.new do
        body 'Hello plain text'
      end

      expect(test_channel.extract_body(mail)).to eq('Hello plain text')
    end

    it 'extracts text from HTML email' do
      mail = Mail.new do
        content_type 'text/html'
        body '<p>Hello <b>world</b></p>'
      end

      result = test_channel.extract_body(mail)
      expect(result).to include('Hello')
      expect(result).to include('world')
      expect(result).not_to include('<b>')
    end

    it 'extracts text/plain from multipart email' do
      mail = Mail.new do
        text_part do
          body 'Plain text version'
        end
        html_part do
          body '<p>HTML version</p>'
        end
      end

      expect(test_channel.extract_body(mail)).to eq('Plain text version')
    end

    it 'falls back to HTML part when no text part in multipart' do
      mail = Mail.new
      mail.content_type = 'multipart/alternative'

      html = Mail::Part.new do
        content_type 'text/html'
        body '<p>Only HTML</p>'
      end
      mail.add_part(html)

      result = test_channel.extract_body(mail)
      expect(result).to include('Only HTML')
    end

    it 'returns error message on extraction failure' do
      mail = double('mail', multipart?: false, content_type: 'text/plain')
      allow(mail).to receive(:decoded).and_raise(StandardError, 'decode error')

      expect(test_channel.extract_body(mail)).to eq('(could not extract email body)')
    end
  end

  describe '#html_to_text' do
    it 'converts <br> tags to newlines' do
      expect(test_channel.html_to_text('Hello<br>World')).to eq("Hello\nWorld")
      expect(test_channel.html_to_text('Hello<br/>World')).to eq("Hello\nWorld")
      expect(test_channel.html_to_text('Hello<br />World')).to eq("Hello\nWorld")
    end

    it 'converts closing </p> tags to newlines' do
      expect(test_channel.html_to_text('<p>Para 1</p><p>Para 2</p>')).to eq("Para 1\nPara 2\n")
    end

    it 'strips all other HTML tags' do
      expect(test_channel.html_to_text('<b>bold</b> <i>italic</i>')).to eq('bold italic')
    end

    it 'unescapes HTML entities' do
      expect(test_channel.html_to_text('&amp; &lt; &gt;')).to eq('& < >')
    end
  end

  describe '#reply_subject' do
    it 'adds subject_prefix to subject' do
      expect(test_channel.reply_subject('Help needed')).to eq('Re: Help needed')
    end

    it 'does not double-add Re: prefix' do
      expect(test_channel.reply_subject('Re: Help needed')).to eq('Re: Help needed')
    end

    it 'handles case-insensitive Re: check' do
      expect(test_channel.reply_subject('RE: Help needed')).to eq('RE: Help needed')
      expect(test_channel.reply_subject('re: Help needed')).to eq('re: Help needed')
    end

    it 'uses default subject for empty string' do
      expect(test_channel.reply_subject('')).to eq('Re: nanobot reply')
      expect(test_channel.reply_subject('   ')).to eq('Re: nanobot reply')
    end
  end

  describe '#fetch_new_messages' do
    let(:imap) { instance_double(Net::IMAP) }

    before do
      allow(Net::IMAP).to receive(:new).and_return(imap)
      allow(imap).to receive(:login)
      allow(imap).to receive(:select)
      allow(imap).to receive(:search).and_return([])
      allow(imap).to receive(:logout)
      allow(imap).to receive(:disconnect)
    end

    it 'connects to IMAP with correct settings' do
      test_channel.fetch_new_messages

      expect(Net::IMAP).to have_received(:new).with('imap.example.com', port: 993, ssl: true)
      expect(imap).to have_received(:login).with('bot@example.com', 'imap-secret')
      expect(imap).to have_received(:select).with('INBOX')
    end

    it 'skips already processed UIDs' do
      test_channel.instance_variable_get(:@processed_uids).add(100)

      raw_email = "From: user@test.com\r\nSubject: Hello\r\n\r\nBody text"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })

      allow(imap).to receive(:search).and_return([100, 101])
      allow(imap).to receive(:fetch).with(100, 'RFC822').and_return([fetch_data])
      allow(imap).to receive(:fetch).with(101, 'RFC822').and_return([fetch_data])
      allow(imap).to receive(:store)
      allow(bus).to receive(:publish_inbound)

      messages = test_channel.fetch_new_messages

      # UID 100 was already processed, only 101 should be returned
      expect(messages.size).to eq(1)
    end

    it 'filters by allow_from list' do
      allow_config = Nanobot::Config::EmailConfig.new(
        consent_granted: true,
        imap_host: 'imap.example.com',
        imap_port: 993,
        imap_username: 'bot@example.com',
        imap_password: 'imap-secret',
        imap_use_ssl: true,
        smtp_host: 'smtp.example.com',
        smtp_username: 'bot@example.com',
        smtp_password: 'smtp-secret',
        allow_from: ['allowed@test.com']
      )
      ch = test_channel_class.new(name: 'email', config: allow_config, bus: bus, logger: logger)
      ch.instance_variable_set(:@processed_uids, Set.new)
      ch.instance_variable_set(:@last_subject_by_chat, {})
      ch.instance_variable_set(:@last_message_id_by_chat, {})

      allowed_email = "From: allowed@test.com\r\nSubject: OK\r\n\r\nAllowed"
      blocked_email = "From: blocked@test.com\r\nSubject: Nope\r\n\r\nBlocked"

      allowed_data = double('fetch_data', attr: { 'RFC822' => allowed_email })
      blocked_data = double('fetch_data', attr: { 'RFC822' => blocked_email })

      allow(imap).to receive(:search).and_return([1, 2])
      allow(imap).to receive(:fetch).with(1, 'RFC822').and_return([allowed_data])
      allow(imap).to receive(:fetch).with(2, 'RFC822').and_return([blocked_data])
      allow(imap).to receive(:store)

      messages = ch.fetch_new_messages

      expect(messages.size).to eq(1)
      expect(messages.first[:sender]).to eq('allowed@test.com')
    end

    it 'marks messages as seen when mark_seen is true' do
      raw_email = "From: user@test.com\r\nSubject: Hello\r\n\r\nBody"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })

      allow(imap).to receive_messages(search: [1], fetch: [fetch_data])
      allow(imap).to receive(:store)

      test_channel.fetch_new_messages

      expect(imap).to have_received(:store).with(1, '+FLAGS', [:Seen])
    end

    it 'does not mark seen when mark_seen is false' do
      no_mark_config = Nanobot::Config::EmailConfig.new(
        consent_granted: true,
        imap_host: 'imap.example.com',
        imap_username: 'bot@example.com',
        imap_password: 'imap-secret',
        smtp_host: 'smtp.example.com',
        smtp_username: 'bot@example.com',
        smtp_password: 'smtp-secret',
        mark_seen: false
      )
      ch = test_channel_class.new(name: 'email', config: no_mark_config, bus: bus, logger: logger)
      ch.instance_variable_set(:@processed_uids, Set.new)
      ch.instance_variable_set(:@last_subject_by_chat, {})
      ch.instance_variable_set(:@last_message_id_by_chat, {})

      raw_email = "From: user@test.com\r\nSubject: Hello\r\n\r\nBody"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })

      allow(imap).to receive_messages(search: [1], fetch: [fetch_data])
      allow(imap).to receive(:store)

      ch.fetch_new_messages

      expect(imap).not_to have_received(:store)
    end

    it 'truncates body to max_body_chars' do
      long_body = 'x' * 20_000
      raw_email = "From: user@test.com\r\nSubject: Hello\r\n\r\n#{long_body}"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })

      allow(imap).to receive_messages(search: [1], fetch: [fetch_data])
      allow(imap).to receive(:store)

      messages = test_channel.fetch_new_messages

      # The body portion (after headers in content) should be truncated
      body_in_content = messages.first[:content].split("\n\n", 2).last
      expect(body_in_content.length).to be <= config.max_body_chars
    end

    it 'caps processed UIDs set at MAX_PROCESSED_UIDS' do
      # Fill processed_uids to just under the limit
      uids_set = test_channel.instance_variable_get(:@processed_uids)
      (1..described_class::MAX_PROCESSED_UIDS).each { |i| uids_set.add(i) }

      raw_email = "From: user@test.com\r\nSubject: Hello\r\n\r\nBody"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })
      new_uid = described_class::MAX_PROCESSED_UIDS + 1

      allow(imap).to receive_messages(search: [new_uid], fetch: [fetch_data])
      allow(imap).to receive(:store)

      test_channel.fetch_new_messages

      # After exceeding MAX_PROCESSED_UIDS, the set should have been cleared
      # then the new UID added
      expect(uids_set.size).to be <= 1
    end

    it 'always disconnects IMAP even on error' do
      allow(imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new(
                                                 double('resp',
                                                        data: double('data',
                                                                     text: 'auth failed'))
                                               ))

      expect { test_channel.fetch_new_messages }.to raise_error(Net::IMAP::NoResponseError)

      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end

    it 'returns metadata with message_id, subject, and sender_email' do
      raw_email = "From: user@test.com\r\nSubject: Test Subject\r\nMessage-ID: <msg123@test.com>\r\n\r\nBody"
      fetch_data = double('fetch_data', attr: { 'RFC822' => raw_email })

      allow(imap).to receive_messages(search: [1], fetch: [fetch_data])
      allow(imap).to receive(:store)

      messages = test_channel.fetch_new_messages

      expect(messages.first[:metadata]).to include(
        'subject' => 'Test Subject',
        'sender_email' => 'user@test.com',
        'message_id' => 'msg123@test.com'
      )
    end
  end
end
