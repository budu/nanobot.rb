# Plan: Channels Implementation

## Goal

Add working channel implementations (Telegram, Discord, HTTP Gateway, Slack, Email) to nanobot.rb, allowing a single process to serve as an AI assistant across multiple platforms simultaneously alongside the existing CLI interface.

## Current State

The runtime infrastructure already exists:

- **`Channels::BaseChannel`** — abstract base with `start`, `stop`, `send`, `allowed?`, `handle_message`
- **`Channels::Manager`** — starts channels in threads, wires outbound bus subscribers, joins on stop
- **`Bus::MessageBus`** — thread-safe inbound/outbound queues with dispatch loop
- **`Bus::InboundMessage` / `OutboundMessage`** — event structs with channel, sender_id, chat_id
- **`Agent::Loop#run`** — bus-consuming loop (consume_inbound -> process_message -> publish_outbound)
- **`Session::Manager`** — keyed by `channel:chat_id`, already supports multi-channel session isolation

What was removed (and needs to be re-added):

- Config structs for channel settings (Telegram, Discord, Gateway, Slack, Email)
- Concrete channel implementations
- CLI wiring to start channels from a `serve` command
- The `telegram-bot-ruby` dependency (and new ones for Discord/Slack)

## Lessons from the Python Implementation

The upstream Python nanobot has evolved significantly since our initial port. Key patterns to adopt:

1. **Error isolation in channel startup** — each channel's `start()` is wrapped in a try/except so one channel failure doesn't crash others
2. **Slash commands** (`/new`, `/help`) — handled uniformly across all channels before LLM processing
3. **Typing indicators** — Telegram sends periodic "typing..." status while processing
4. **Metadata passthrough** — channel-specific metadata (e.g., Slack `thread_ts`) flows through InboundMessage → agent → OutboundMessage for thread-aware replies
5. **Consent gating** — Email channel requires explicit `consent_granted: true` before accessing mailbox
6. **Group message policies** — Slack uses `mention`/`open`/`allowlist` policies for group channels
7. **Reconnect loops** — channels wrap their main loop in retry logic with delays

## Phases

### Phase 1: Config and CLI Foundation

Re-introduce channel configuration and add a `serve` CLI command separate from the existing `agent` command. Also adopt error isolation from the start.

**1.1 Config schema changes (`lib/nanobot/config/schema.rb`)**

Add channel config structs, one per channel type. Keep them minimal — only fields the implementation actually reads:

```ruby
TelegramConfig = Struct.new(:enabled, :token, :allow_from, :proxy, keyword_init: true) do
  def initialize(enabled: false, token: nil, allow_from: [], proxy: nil)
    super
  end
end

DiscordConfig = Struct.new(:enabled, :token, :allow_from, keyword_init: true) do
  def initialize(enabled: false, token: nil, allow_from: [])
    super
  end
end

GatewayConfig = Struct.new(:enabled, :host, :port, :auth_token, keyword_init: true) do
  def initialize(enabled: false, host: '127.0.0.1', port: 18_790, auth_token: nil)
    super
  end
end

SlackDMConfig = Struct.new(:enabled, :policy, :allow_from, keyword_init: true) do
  def initialize(enabled: true, policy: 'open', allow_from: [])
    super
  end
end

SlackConfig = Struct.new(:enabled, :bot_token, :app_token, :group_policy,
                         :group_allow_from, :dm, keyword_init: true) do
  def initialize(enabled: false, bot_token: nil, app_token: nil,
                 group_policy: 'mention', group_allow_from: [], dm: {})
    super(
      enabled: enabled, bot_token: bot_token, app_token: app_token,
      group_policy: group_policy, group_allow_from: group_allow_from,
      dm: SlackDMConfig.new(**dm)
    )
  end
end

EmailConfig = Struct.new(:enabled, :consent_granted,
                         :imap_host, :imap_port, :imap_username, :imap_password,
                         :imap_mailbox, :imap_use_ssl,
                         :smtp_host, :smtp_port, :smtp_username, :smtp_password,
                         :smtp_use_tls, :smtp_use_ssl, :from_address,
                         :auto_reply_enabled, :poll_interval_seconds, :mark_seen,
                         :max_body_chars, :subject_prefix, :allow_from,
                         keyword_init: true) do
  def initialize(enabled: false, consent_granted: false,
                 imap_host: nil, imap_port: 993, imap_username: nil, imap_password: nil,
                 imap_mailbox: 'INBOX', imap_use_ssl: true,
                 smtp_host: nil, smtp_port: 587, smtp_username: nil, smtp_password: nil,
                 smtp_use_tls: true, smtp_use_ssl: false, from_address: nil,
                 auto_reply_enabled: true, poll_interval_seconds: 30, mark_seen: true,
                 max_body_chars: 12_000, subject_prefix: 'Re: ', allow_from: [])
    super
  end
end

ChannelsConfig = Struct.new(:telegram, :discord, :gateway, :slack, :email,
                            keyword_init: true) do
  def initialize(telegram: {}, discord: {}, gateway: {}, slack: {}, email: {})
    super(
      telegram: TelegramConfig.new(**telegram),
      discord: DiscordConfig.new(**discord),
      gateway: GatewayConfig.new(**gateway),
      slack: SlackConfig.new(**slack),
      email: EmailConfig.new(**email)
    )
  end
end
```

Add `channels` back to the `Config` struct. Keep `**_rest` so unknown keys are still ignored.

**1.2 Config loader changes (`lib/nanobot/config/loader.rb`)**

Add `channels_to_hash` serialization. Only serialize non-default values to keep config files clean.

**1.3 New CLI command: `serve` (`lib/nanobot/cli/commands.rb`)**

Add a `serve` subcommand that starts the agent in multi-channel daemon mode:

```ruby
desc 'serve', 'Start nanobot as a multi-channel service'
method_option :debug, aliases: '-d', type: :boolean, default: false
def serve
  config = load_config
  # ... setup provider, bus, agent_loop ...
  manager = Channels::Manager.new(config: config, bus: bus, logger: logger)

  # Register enabled channels (lazy require, error isolation)
  register_channels(manager, config, bus, logger)

  # Start everything
  manager.start_all

  # Run agent loop on main thread (consumes from bus)
  trap('INT') { agent_loop.stop; manager.stop_all }
  trap('TERM') { agent_loop.stop; manager.stop_all }
  agent_loop.run
end
```

The existing `agent` command stays unchanged — it uses `process_direct` and never touches the bus dispatch.

**1.4 Error-isolated channel registration**

Adopt the Python pattern of wrapping each channel start in error handling from the start, rather than deferring to Phase 5:

```ruby
def start_channel_with_isolation(name, channel)
  Thread.new do
    begin
      @logger.info "Starting channel: #{name}"
      channel.start
    rescue StandardError => e
      @logger.error "Channel #{name} failed: #{e.message}"
    end
  end
end
```

**1.5 Update `status` command**

Show enabled channels and their connection state.

**1.6 Slash command handling in agent loop**

Handle `/new` and `/help` commands uniformly before LLM processing, matching the Python implementation:

```ruby
def process_message(msg)
  case msg.content.strip
  when '/new'
    session = @sessions.get_or_create(msg.session_key)
    session.clear
    @sessions.save(session)
    return OutboundMessage.new(channel: msg.channel, chat_id: msg.chat_id,
                               content: 'New session started.')
  when '/help'
    return OutboundMessage.new(channel: msg.channel, chat_id: msg.chat_id,
                               content: help_text)
  end
  # ... normal LLM processing ...
end
```

---

### Phase 2: Telegram Channel

The most straightforward channel to implement. Telegram's bot API is request/response, the `telegram-bot-ruby` gem handles long-polling, and message routing is simple.

**2.1 Add dependency**

Add `telegram-bot-ruby` to Gemfile and gemspec as an optional dependency. Use `begin/rescue LoadError` to give a clear error if missing:

```ruby
# lib/nanobot/channels/telegram.rb
begin
  require 'telegram/bot'
rescue LoadError
  raise LoadError, "telegram-bot-ruby gem is required for Telegram channel. Add it to your Gemfile."
end
```

**2.2 Implement `Channels::Telegram` (`lib/nanobot/channels/telegram.rb`)**

```ruby
module Nanobot
  module Channels
    class Telegram < BaseChannel
      def start
        @running = true
        ::Telegram::Bot::Client.run(@config.token) do |bot|
          @bot = bot
          register_commands(bot)
          bot.listen do |message|
            break unless @running
            next unless message.is_a?(::Telegram::Bot::Types::Message)
            next unless message.text

            handle_message(
              sender_id: message.from.id.to_s,
              chat_id: message.chat.id.to_s,
              content: message.text
            )
          end
        end
      end

      def stop
        @running = false
      end

      def send(message)
        return unless @bot

        split_message(message.content, 4096).each do |chunk|
          @bot.api.send_message(chat_id: message.chat_id, text: chunk)
        end
      end

      private

      def register_commands(bot)
        bot.api.set_my_commands(commands: [
          { command: 'new', description: 'Start a new session' },
          { command: 'help', description: 'Show help' }
        ])
      end

      def split_message(text, limit)
        text.chars.each_slice(limit).map(&:join)
      end
    end
  end
end
```

Key decisions:
- `sender_id` uses Telegram user ID (numeric, converted to string)
- `chat_id` uses Telegram chat ID (supports both private and group chats)
- ACL via `allow_from` checks Telegram user IDs
- Long-polling via `bot.listen` — simple, no webhook infrastructure needed
- Register `/new` and `/help` in Telegram's command menu
- 4096-character message splitting

**2.3 Typing indicator**

Send periodic "typing..." action while processing, matching the Python implementation:

```ruby
def handle_message(sender_id:, chat_id:, content:, media: [])
  start_typing(chat_id)
  super
end

def start_typing(chat_id)
  @typing_threads ||= {}
  @typing_threads[chat_id] = Thread.new do
    loop do
      @bot&.api&.send_chat_action(chat_id: chat_id, action: 'typing')
      sleep 4
    rescue StandardError
      break
    end
  end
end

def stop_typing(chat_id)
  @typing_threads&.delete(chat_id)&.kill
end

def send(message)
  stop_typing(message.chat_id)
  # ... send as before ...
end
```

**2.4 Tests**

- Unit test `Channels::Telegram` with a mocked `Telegram::Bot::Client`
- Integration test: start channel, simulate inbound message, verify it reaches the bus
- Test ACL (allow_from filtering)
- Test message splitting for long responses
- Test typing indicator lifecycle

---

### Phase 3: HTTP Gateway Channel

A simple HTTP API that accepts messages and returns responses. Useful for custom integrations, webhooks, and programmatic access.

**3.1 Dependencies**

Use WEBrick (stdlib) or the `webrick` gem (extracted from stdlib in Ruby 3.0+). No additional dependencies needed.

**3.2 Implement `Channels::Gateway` (`lib/nanobot/channels/gateway.rb`)**

```ruby
require 'webrick'
require 'json'

module Nanobot
  module Channels
    class Gateway < BaseChannel
      def start
        @running = true
        @response_queues = {}
        @mutex = Mutex.new

        # Subscribe to outbound messages to route responses back
        @bus.subscribe_outbound(@name) do |message|
          queue = @mutex.synchronize { @response_queues.delete(message.chat_id) }
          queue&.push(message)
        end

        @server = WEBrick::HTTPServer.new(
          Port: @config.port,
          BindAddress: @config.host,
          Logger: WEBrick::Log.new(IO::NULL),
          AccessLog: []
        )

        @server.mount_proc '/chat' do |req, res|
          handle_http_request(req, res)
        end

        @server.mount_proc '/health' do |_req, res|
          res.content_type = 'application/json'
          res.body = JSON.generate({ status: 'ok' })
        end

        @server.start
      end

      def stop
        @running = false
        @server&.shutdown
      end

      def send(message)
        # Responses are routed via response_queues in start
      end

      private

      def handle_http_request(req, res)
        return method_not_allowed(res) unless req.request_method == 'POST'
        return unauthorized(res) unless authorized?(req)

        body = JSON.parse(req.body)
        chat_id = body['chat_id'] || SecureRandom.uuid
        content = body['message']

        return bad_request(res, 'missing "message" field') unless content

        # Create a response queue for this request
        queue = Queue.new
        @mutex.synchronize { @response_queues[chat_id] = queue }

        # Publish inbound message
        handle_message(
          sender_id: 'api',
          chat_id: chat_id,
          content: content
        )

        # Wait for response (with timeout)
        begin
          response = Timeout.timeout(120) { queue.pop }
          res.content_type = 'application/json'
          res.body = JSON.generate({
            chat_id: chat_id,
            response: response.content
          })
        rescue Timeout::Error
          res.status = 504
          res.content_type = 'application/json'
          res.body = JSON.generate({ error: 'timeout' })
        end
      end

      def authorized?(req)
        return true unless @config.auth_token
        req['Authorization'] == "Bearer #{@config.auth_token}"
      end
    end
  end
end
```

Key design:
- Synchronous request/response: the HTTP handler publishes an inbound message, then blocks on a `Queue` waiting for the outbound response
- `chat_id` can be provided by the caller for session continuity, or auto-generated for one-shot queries
- Bearer token auth via `GatewayConfig.auth_token`
- `/health` endpoint for monitoring
- 120-second timeout for LLM processing

**3.3 API contract**

```
POST /chat
Content-Type: application/json
Authorization: Bearer <token>   # optional, if auth_token configured

{
  "message": "What is the weather?",
  "chat_id": "session-123"       # optional, for session continuity
}

Response 200:
{
  "chat_id": "session-123",
  "response": "I don't have real-time weather access..."
}
```

**3.4 Tests**

- Unit test HTTP handler with mock bus
- Test auth token validation
- Test session continuity (same chat_id across requests)
- Test timeout behavior
- Test health endpoint

---

### Phase 4: Discord Channel

More complex than Telegram due to Discord's gateway WebSocket connection, intents system, and message model.

**4.1 Dependencies**

Add `discordrb` gem (the maintained Ruby Discord library). Like Telegram, make it a soft/optional dependency.

**4.2 Implement `Channels::Discord` (`lib/nanobot/channels/discord.rb`)**

```ruby
begin
  require 'discordrb'
rescue LoadError
  raise LoadError, "discordrb gem is required for Discord channel. Add it to your Gemfile."
end

module Nanobot
  module Channels
    class Discord < BaseChannel
      def start
        @running = true
        @bot = Discordrb::Bot.new(token: @config.token, intents: [:server_messages])

        @bot.message do |event|
          next if event.author.bot_account?  # ignore bot messages
          next unless allowed?(event.author.id.to_s)

          handle_message(
            sender_id: event.author.id.to_s,
            chat_id: event.channel.id.to_s,
            content: event.content
          )
        end

        @bot.run
      end

      def stop
        @running = false
        @bot&.stop
      end

      def send(message)
        channel = @bot.channel(message.chat_id.to_i)
        return unless channel

        split_message(message.content, 2000).each do |chunk|
          channel.send_message(chunk)
        end
      end

      private

      def split_message(text, limit)
        text.chars.each_slice(limit).map(&:join)
      end
    end
  end
end
```

Key decisions:
- Use `intents: [:server_messages]` for minimal permissions
- Filter out bot messages to prevent loops
- `chat_id` is the Discord channel ID, so sessions are per-channel
- 2000-character message limit splitting
- ACL via Discord user IDs

**4.3 Tests**

- Unit test with mocked `Discordrb::Bot`
- Test bot message filtering
- Test message splitting
- Test ACL

---

### Phase 5: Slack Channel

Slack uses Socket Mode for real-time messaging. More complex than Telegram due to group policies, thread awareness, and mention handling.

**5.1 Dependencies**

Add `slack-ruby-client` gem as an optional dependency. It provides both the Web API client and Socket Mode support.

```ruby
# lib/nanobot/channels/slack.rb
begin
  require 'slack-ruby-client'
rescue LoadError
  raise LoadError, "slack-ruby-client gem is required for Slack channel. Add it to your Gemfile."
end
```

**5.2 Implement `Channels::Slack` (`lib/nanobot/channels/slack.rb`)**

```ruby
module Nanobot
  module Channels
    class Slack < BaseChannel
      def start
        @running = true
        @bot_user_id = nil

        Slack.configure do |c|
          c.token = @config.bot_token
        end

        @web_client = Slack::Web::Client.new
        @socket_client = Slack::RealTime::Client.new(token: @config.app_token)

        # Resolve bot user ID for mention handling
        begin
          auth = @web_client.auth_test
          @bot_user_id = auth['user_id']
          @logger.info "Slack bot connected as #{@bot_user_id}"
        rescue StandardError => e
          @logger.warn "Slack auth_test failed: #{e.message}"
        end

        @socket_client.on :message do |data|
          handle_slack_message(data)
        end

        @socket_client.start!
      end

      def stop
        @running = false
        @socket_client&.stop!
      end

      def send(message)
        return unless @web_client

        slack_meta = (message.metadata || {}).dig('slack') || {}
        thread_ts = slack_meta['thread_ts']
        channel_type = slack_meta['channel_type']
        # Only reply in thread for channel/group messages; DMs don't use threads
        use_thread = thread_ts && channel_type != 'im'

        @web_client.chat_postMessage(
          channel: message.chat_id,
          text: message.content || '',
          thread_ts: use_thread ? thread_ts : nil
        )
      end

      private

      def handle_slack_message(data)
        return if data['subtype'] # ignore bot/system messages
        return if @bot_user_id && data['user'] == @bot_user_id

        sender_id = data['user']
        chat_id = data['channel']
        text = data['text'] || ''
        channel_type = data['channel_type'] || ''

        return unless sender_id && chat_id
        return unless allowed_slack?(sender_id, chat_id, channel_type)

        # For group channels, check group policy
        if channel_type != 'im'
          return unless should_respond_in_channel?(text, chat_id)
        end

        # Avoid double-processing mentions (Slack sends both message and app_mention)
        if @bot_user_id && text.include?("<@#{@bot_user_id}>")
          # Let app_mention handle it instead
          return
        end

        text = strip_bot_mention(text)
        thread_ts = data['thread_ts'] || data['ts']

        # Add :eyes: reaction (best-effort)
        add_eyes_reaction(chat_id, data['ts'])

        handle_message(
          sender_id: sender_id,
          chat_id: chat_id,
          content: text,
          metadata: {
            'slack' => {
              'thread_ts' => thread_ts,
              'channel_type' => channel_type
            }
          }
        )
      end

      def allowed_slack?(sender_id, chat_id, channel_type)
        if channel_type == 'im'
          return false unless @config.dm.enabled
          return @config.dm.policy != 'allowlist' ||
                 @config.dm.allow_from.include?(sender_id)
        end

        # Group/channel messages
        return true unless @config.group_policy == 'allowlist'
        @config.group_allow_from.include?(chat_id)
      end

      def should_respond_in_channel?(text, chat_id)
        case @config.group_policy
        when 'open' then true
        when 'mention'
          @bot_user_id && text.include?("<@#{@bot_user_id}>")
        when 'allowlist'
          @config.group_allow_from.include?(chat_id)
        else false
        end
      end

      def strip_bot_mention(text)
        return text unless @bot_user_id
        text.gsub(/<@#{Regexp.escape(@bot_user_id)}>\s*/, '').strip
      end

      def add_eyes_reaction(channel, timestamp)
        return unless @web_client && timestamp
        @web_client.reactions_add(channel: channel, name: 'eyes', timestamp: timestamp)
      rescue StandardError => e
        @logger.debug "Slack reactions_add failed: #{e.message}"
      end
    end
  end
end
```

Key decisions:
- Socket Mode — no public URL required, uses WebSocket via app token
- Resolves bot user ID at startup for mention detection
- **DM policy**: `open` (accept all) or `allowlist` (check user IDs)
- **Group policy**: `mention` (only respond when @mentioned), `open` (respond to all), `allowlist` (only specific channels)
- Thread-aware replies: passes `thread_ts` through metadata, replies in-thread for group messages but not DMs
- Adds `:eyes:` reaction to acknowledge received messages
- Strips `<@bot_id>` from message text before forwarding
- Deduplicates mention events (Slack sends both `message` and `app_mention`)

**5.3 Tests**

- Unit test with mocked Slack clients
- Test DM policy (open vs allowlist)
- Test group policy (mention, open, allowlist)
- Test thread-aware replies
- Test bot mention stripping
- Test ACL

---

### Phase 6: Email Channel

Email uses IMAP polling for inbound and SMTP for outbound. Requires explicit consent before accessing mailbox data.

**6.1 Dependencies**

No external gems needed — Ruby stdlib provides `net/imap` and `net/smtp`. The `mail` gem can be used for parsing but stdlib is sufficient.

**6.2 Implement `Channels::Email` (`lib/nanobot/channels/email.rb`)**

```ruby
require 'net/imap'
require 'net/smtp'
require 'mail'

module Nanobot
  module Channels
    class Email < BaseChannel
      MAX_PROCESSED_UIDS = 100_000

      def start
        unless @config.consent_granted
          @logger.warn "Email channel disabled: consent_granted is false. " \
                       "Set channels.email.consent_granted=true after explicit user permission."
          return
        end

        unless valid_config?
          return
        end

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
          @logger.warn "Skip email send: consent_granted is false"
          return
        end

        force_send = (message.metadata || {})['force_send']
        unless @config.auto_reply_enabled || force_send
          @logger.info "Skip automatic email reply: auto_reply_enabled is false"
          return
        end

        to_addr = message.chat_id.strip
        return if to_addr.empty?

        base_subject = @last_subject_by_chat[to_addr] || 'nanobot reply'
        subject = reply_subject(base_subject)

        mail = Mail.new do
          to      to_addr
          subject subject
          body    message.content || ''
        end
        mail.from = @config.from_address || @config.smtp_username

        # Thread via In-Reply-To
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

          uids = imap.search(['UNSEEN'])
          uids.each do |uid|
            next if @processed_uids.include?(uid)

            data = imap.fetch(uid, 'RFC822')&.first
            next unless data

            raw = data.attr['RFC822']
            parsed = Mail.new(raw)
            sender = parsed.from&.first&.downcase
            next unless sender
            next if @config.allow_from.any? && !@config.allow_from.include?(sender)

            subject = parsed.subject || ''
            message_id = parsed.message_id || ''
            body = extract_body(parsed)
            body = body[0...@config.max_body_chars]

            content = "Email received.\nFrom: #{sender}\nSubject: #{subject}\n" \
                      "Date: #{parsed.date}\n\n#{body}"

            messages << {
              sender: sender,
              subject: subject,
              message_id: message_id,
              content: content,
              metadata: {
                'message_id' => message_id,
                'subject' => subject,
                'sender_email' => sender
              }
            }

            @processed_uids.add(uid)
            @processed_uids.clear if @processed_uids.size > MAX_PROCESSED_UIDS

            imap.store(uid, '+FLAGS', [:Seen]) if @config.mark_seen
          end
        ensure
          imap.logout rescue nil
          imap.disconnect rescue nil
        end

        messages
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
        html.gsub(/<\s*br\s*\/?>/, "\n")
            .gsub(/<\s*\/\s*p\s*>/, "\n")
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
```

Key decisions:
- **Consent gating**: will not start or send unless `consent_granted: true` — privacy safeguard
- **IMAP polling**: configurable interval (min 5s), searches for UNSEEN messages
- **UID deduplication**: tracks processed UIDs with a capped set (100K max) to prevent unbounded growth
- **Threading**: maintains `In-Reply-To` and `References` headers for email thread continuity
- **Auto-reply toggle**: `auto_reply_enabled` can be false to read-only (useful for email summarization skills)
- **Allow list**: filters by sender email address
- **Body extraction**: prefers text/plain, falls back to HTML→text conversion
- `chat_id` is the sender's email address, so sessions are per-sender

**6.3 Tests**

- Unit test with mocked IMAP/SMTP
- Test consent gating (disabled when consent_granted is false)
- Test UID deduplication
- Test email body extraction (plain, HTML, multipart)
- Test reply threading (In-Reply-To headers)
- Test allow_from filtering
- Test auto_reply_enabled toggle

---

### Phase 7: Infrastructure Hardening

Address thread safety and resilience issues that become critical once channels are running in production.

**7.1 Channel thread supervision (`lib/nanobot/channels/manager.rb`)**

Add reconnect logic with backoff for crashed channel threads:

```ruby
def start_channel_with_supervision(name, channel, max_restarts: 3)
  restarts = 0
  thread = Thread.new do
    loop do
      begin
        @logger.info "Starting channel: #{name}"
        channel.start
        break  # clean exit
      rescue StandardError => e
        restarts += 1
        if restarts <= max_restarts
          delay = 5 * restarts  # linear backoff
          @logger.warn "Channel #{name} crashed (#{restarts}/#{max_restarts}), restarting in #{delay}s: #{e.message}"
          sleep delay
        else
          @logger.error "Channel #{name} exceeded max restarts, giving up: #{e.message}"
          break
        end
      end
    end
  end
  @threads << thread
end
```

**7.2 Dispatch loop resilience (`lib/nanobot/bus/message_bus.rb`)**

Wrap `dispatch_message` in per-message error handling so one bad message doesn't kill the dispatcher:

```ruby
def dispatch_loop
  loop do
    break unless @running
    message = @outbound_queue.pop
    break unless message

    begin
      dispatch_message(message)
    rescue StandardError => e
      @logger.error "Error dispatching message: #{e.message}"
    end
  end
end
```

**7.3 Graceful shutdown**

Handle SIGTERM in addition to SIGINT. Ensure channels drain their queues before stopping. Add a shutdown timeout to prevent hanging.

**7.4 Replace `Timeout.timeout` in bus**

For the inbound queue consume, use `Queue#pop(timeout:)` (Ruby 3.2+) or a polling approach instead of `Timeout.timeout`.

---

### Phase 8: Testing and Documentation

**8.1 Integration tests**

- Full round-trip: channel receives message -> bus -> agent -> bus -> channel sends response
- Multi-channel: two channels running simultaneously with independent sessions
- Graceful shutdown: verify all channels stop and threads join
- Slash commands: verify `/new` and `/help` work across all channels

**8.2 Config file documentation**

Update the example config in `create_default` to include channel configuration (all disabled by default):

```json
{
  "channels": {
    "telegram": { "enabled": false, "token": "YOUR_TELEGRAM_BOT_TOKEN" },
    "discord": { "enabled": false, "token": "YOUR_DISCORD_BOT_TOKEN" },
    "gateway": { "enabled": false, "port": 18790 },
    "slack": {
      "enabled": false,
      "bot_token": "xoxb-YOUR-BOT-TOKEN",
      "app_token": "xapp-YOUR-APP-TOKEN",
      "group_policy": "mention"
    },
    "email": {
      "enabled": false,
      "consent_granted": false,
      "imap_host": "imap.gmail.com",
      "smtp_host": "smtp.gmail.com"
    }
  }
}
```

**8.3 README updates**

- Add a "Multi-Channel Mode" section
- Document the `serve` command
- Document the HTTP Gateway API
- Add setup instructions for Telegram, Discord, Slack, and Email

## Implementation Order

1. **Phase 1** (Config + CLI + slash commands) — foundation, no new dependencies
2. **Phase 3** (HTTP Gateway) — no external dependencies (WEBrick), easiest to test, immediately useful for API integrations
3. **Phase 2** (Telegram) — one new dependency, straightforward API
4. **Phase 7** (Hardening) — make it production-ready before adding more complex channels
5. **Phase 4** (Discord) — most complex platform integration, benefits from hardened infrastructure
6. **Phase 5** (Slack) — Socket Mode, group policies, thread awareness
7. **Phase 6** (Email) — IMAP/SMTP, consent gating, no external deps
8. **Phase 8** (Testing + Docs) — ongoing throughout, but final polish here

## Dependencies Added

| Channel  | Gem                 | Optional? | Notes                       |
|----------|---------------------|-----------|-----------------------------|
| Telegram | `telegram-bot-ruby` | Yes       | Only loaded when enabled    |
| Discord  | `discordrb`         | Yes       | Only loaded when enabled    |
| Gateway  | `webrick`           | No        | May already be available    |
| Slack    | `slack-ruby-client` | Yes       | Only loaded when enabled    |
| Email    | `mail`              | Yes       | For parsing; stdlib fallback possible |

All channel gems should be optional — listed in Gemfile but not in gemspec runtime dependencies. Users install what they need. The channel code uses `begin/rescue LoadError` to give a clear error message if the gem is missing.

## Open Questions

1. **Should channels be separate gems?** e.g. `nanobot-telegram`, `nanobot-discord`. This would keep the core gem truly minimal. However, it adds packaging complexity. For now, optional requires in the main gem is simpler.

2. **Should the Gateway use Rack instead of WEBrick?** Rack would allow users to deploy behind Puma/Unicorn, but adds a dependency and complexity. WEBrick is good enough for a personal tool. Could offer both via a config option later.

3. **Streaming responses?** The Gateway could support SSE for streaming LLM output. This is a nice-to-have but adds significant complexity to the request/response flow. Defer to a future phase.

4. **Media/file handling?** The `InboundMessage` struct already has a `media` field. Telegram and Discord both support file attachments. Implementing media would require the LLM provider to support multimodal input, which depends on the model. Defer until the core text flow is solid.

5. **Rate limiting?** The Gateway should probably have basic rate limiting to prevent abuse. Could use a simple token bucket per IP or per auth token. Not critical for a personal tool but important if exposed publicly.

6. **Memory consolidation?** The Python nanobot now has a two-layer memory system (MEMORY.md for facts, HISTORY.md for events) that summarizes old session messages. This keeps the context window manageable for long-running sessions. Worth adding as a separate feature, not part of this plan.

7. **Slack Socket Mode gem?** The `slack-ruby-client` gem supports Socket Mode via `Slack::RealTime::Client`, but there's also `slack-ruby-socket-mode-bot`. Need to evaluate which is more maintained and suitable.
