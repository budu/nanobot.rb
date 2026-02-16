# frozen_string_literal: true

require 'net/imap'
require 'cgi'

begin
  require 'mail'
rescue LoadError
  raise LoadError, 'mail gem is required for Email channel. Add it to your Gemfile.'
end

module Nanobot
  module Channels
    class Email < BaseChannel
      MAX_PROCESSED_UIDS = 100_000

      def start
        unless @config.consent_granted
          @logger.warn 'Email channel disabled: consent_granted is false. ' \
                       'Set channels.email.consent_granted=true after explicit user permission.'
          return
        end

        return unless valid_config?

        @running = true
        @processed_uids = Set.new
        @last_subject_by_chat = {}
        @last_message_id_by_chat = {}

        poll_seconds = [@config.poll_interval_seconds, 5].max

        @logger.info "Starting Email channel (IMAP polling every #{poll_seconds}s)..."

        while @running
          begin
            fetch_new_messages.each do |item|
              sender = item[:sender]
              @last_subject_by_chat[sender] = item[:subject] if item[:subject]
              @last_message_id_by_chat[sender] = item[:message_id] if item[:message_id]

              handle_message(
                sender_id: sender,
                chat_id: sender,
                content: item[:content],
                metadata: item[:metadata] || {}
              )
            end
          rescue StandardError => e
            @logger.error "Email polling error: #{e.message}"
          end

          sleep poll_seconds
        end
      end

      def stop
        @running = false
      end

      def send(message)
        unless @config.consent_granted
          @logger.warn 'Skip email send: consent_granted is false'
          return
        end

        force_send = (message.metadata || {})['force_send']
        unless @config.auto_reply_enabled || force_send
          @logger.info 'Skip automatic email reply: auto_reply_enabled is false'
          return
        end

        to_addr = message.chat_id.to_s.strip
        return if to_addr.empty?

        base_subject = @last_subject_by_chat[to_addr] || 'nanobot reply'
        subject = reply_subject(base_subject)

        mail = ::Mail.new
        mail.to = to_addr
        mail.subject = subject
        mail.body = message.content || ''
        mail.from = @config.from_address || @config.smtp_username

        if (ref = @last_message_id_by_chat[to_addr])
          mail['In-Reply-To'] = ref
          mail['References'] = ref
        end

        smtp_send(mail)
      end

      private

      def valid_config?
        missing = []
        missing << 'imap_host' unless @config.imap_host
        missing << 'imap_username' unless @config.imap_username
        missing << 'imap_password' unless @config.imap_password
        missing << 'smtp_host' unless @config.smtp_host
        missing << 'smtp_username' unless @config.smtp_username
        missing << 'smtp_password' unless @config.smtp_password

        if missing.any?
          @logger.error "Email channel not configured, missing: #{missing.join(', ')}"
          return false
        end
        true
      end

      def fetch_new_messages
        messages = []
        imap = Net::IMAP.new(@config.imap_host, port: @config.imap_port,
                                                ssl: @config.imap_use_ssl)
        begin
          imap.login(@config.imap_username, @config.imap_password)
          imap.select(@config.imap_mailbox)

          imap.search(['UNSEEN']).each do |uid|
            next if @processed_uids.include?(uid)

            item = process_uid(imap, uid)
            messages << item if item
          end
        ensure
          imap.logout rescue nil # rubocop:disable Style/RescueModifier
          imap.disconnect rescue nil # rubocop:disable Style/RescueModifier
        end

        messages
      end

      def process_uid(imap, uid)
        data = imap.fetch(uid, 'RFC822')&.first
        return unless data

        parsed = ::Mail.new(data.attr['RFC822'])
        sender = parsed.from&.first&.downcase
        return unless sender
        return if @config.allow_from.any? && !@config.allow_from.include?(sender)

        item = build_message_item(parsed, sender)
        track_uid(imap, uid)
        item
      end

      def build_message_item(parsed, sender)
        subject = parsed.subject || ''
        message_id = parsed.message_id || ''
        body = extract_body(parsed)[0...@config.max_body_chars]

        content = "Email received.\nFrom: #{sender}\nSubject: #{subject}\n" \
                  "Date: #{parsed.date}\n\n#{body}"

        {
          sender: sender, subject: subject, message_id: message_id,
          content: content,
          metadata: { 'message_id' => message_id, 'subject' => subject, 'sender_email' => sender }
        }
      end

      def track_uid(imap, uid)
        @processed_uids.add(uid)
        @processed_uids.clear if @processed_uids.size > MAX_PROCESSED_UIDS
        imap.store(uid, '+FLAGS', [:Seen]) if @config.mark_seen
      end

      def extract_body(mail)
        if mail.multipart?
          text_part = mail.text_part
          return text_part.decoded if text_part

          html_part = mail.html_part
          return html_to_text(html_part.decoded) if html_part

          ''
        elsif mail.content_type&.include?('text/html')
          html_to_text(mail.decoded)
        else
          mail.decoded.to_s
        end
      rescue StandardError
        '(could not extract email body)'
      end

      def html_to_text(html)
        html.gsub(%r{<\s*br\s*/?>}, "\n")
            .gsub(%r{<\s*/\s*p\s*>}, "\n")
            .gsub(/<[^>]+>/, '')
            .then { |t| CGI.unescapeHTML(t) }
      end

      def reply_subject(base)
        subject = base.strip.empty? ? 'nanobot reply' : base.strip
        return subject if subject.downcase.start_with?('re:')

        "#{@config.subject_prefix}#{subject}"
      end

      def smtp_send(mail)
        mail.delivery_method :smtp,
                             address: @config.smtp_host,
                             port: @config.smtp_port,
                             user_name: @config.smtp_username,
                             password: @config.smtp_password,
                             authentication: :login,
                             enable_starttls_auto: @config.smtp_use_tls,
                             ssl: @config.smtp_use_ssl
        mail.deliver
      end
    end
  end
end
