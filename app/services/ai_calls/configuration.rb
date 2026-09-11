# frozen_string_literal: true

module AiCalls
  # Reads every AI-voice-calling-related setting from ENV, mirroring
  # Sms::Configuration/Payments::Configuration's exact pattern -- one place
  # that knows the env var names, so providers/services never touch ENV
  # directly.
  class Configuration
    def elevenlabs_api_key
      ENV['ELEVENLABS_API_KEY'].to_s.strip.presence
    end

    def elevenlabs_base_url
      ENV.fetch('ELEVENLABS_BASE_URL', 'https://api.elevenlabs.io').strip
    end

    def elevenlabs_outbound_agent_id
      ENV['ELEVENLABS_OUTBOUND_AGENT_ID'].to_s.strip.presence
    end

    def elevenlabs_inbound_agent_id
      ENV['ELEVENLABS_INBOUND_AGENT_ID'].to_s.strip.presence
    end

    def elevenlabs_agent_phone_number_id
      ENV['ELEVENLABS_AGENT_PHONE_NUMBER_ID'].to_s.strip.presence
    end

    def elevenlabs_webhook_signing_secret
      ENV['ELEVENLABS_WEBHOOK_SIGNING_SECRET'].to_s.strip.presence
    end

    def elevenlabs_open_timeout
      ENV.fetch('ELEVENLABS_OPEN_TIMEOUT_SECONDS', 5).to_i
    end

    def elevenlabs_read_timeout
      ENV.fetch('ELEVENLABS_READ_TIMEOUT_SECONDS', 15).to_i
    end

    def tool_shared_secret
      ENV['AI_CALLS_TOOL_SHARED_SECRET'].to_s.strip.presence
    end

    def twilio_account_sid
      ENV['TWILIO_ACCOUNT_SID'].to_s.strip.presence
    end

    def twilio_auth_token
      ENV['TWILIO_AUTH_TOKEN'].to_s.strip.presence
    end

    def twilio_base_url
      ENV.fetch('TWILIO_BASE_URL', 'https://api.twilio.com').strip
    end

    def twilio_open_timeout
      ENV.fetch('TWILIO_OPEN_TIMEOUT_SECONDS', 5).to_i
    end

    def twilio_read_timeout
      ENV.fetch('TWILIO_READ_TIMEOUT_SECONDS', 10).to_i
    end

    # Independent feature flags (not one blanket switch) so outbound
    # reminders can go live before the inbound helpline opens, and so
    # recording/human-transfer can be disabled without disabling AI calling
    # entirely.
    def outbound_enabled?
      flag('AI_VOICE_OUTBOUND_ENABLED')
    end

    def inbound_enabled?
      flag('AI_VOICE_INBOUND_ENABLED')
    end

    def recording_enabled?
      flag('AI_VOICE_RECORDING_ENABLED')
    end

    def human_transfer_enabled?
      flag('AI_VOICE_HUMAN_TRANSFER_ENABLED')
    end

    # Operational safety controls for outbound triggering (admin-triggered and
    # workflow-stage-triggered) -- see the plan's "Operational safety
    # controls" section. `outbound_enabled?` above already doubles as the
    # emergency kill switch: flipping it off stops every outbound trigger
    # immediately, so a second redundant flag isn't introduced.
    def outbound_trigger_cooldown_minutes
      ENV.fetch('AI_VOICE_OUTBOUND_TRIGGER_COOLDOWN_MINUTES', 60).to_i
    end

    def daily_outbound_call_limit
      ENV.fetch('AI_VOICE_DAILY_OUTBOUND_CALL_LIMIT', 200).to_i
    end

    def admin_trigger_rate_limit_per_hour
      ENV.fetch('AI_VOICE_ADMIN_TRIGGER_RATE_LIMIT_PER_HOUR', 50).to_i
    end

    # Pakistan-local allowed calling hours (24h clock, start inclusive, end
    # exclusive).
    def calling_hours_start
      ENV.fetch('AI_VOICE_CALLING_HOURS_START', 9).to_i
    end

    def calling_hours_end
      ENV.fetch('AI_VOICE_CALLING_HOURS_END', 19).to_i
    end

    # Used both as the reconciliation job's `in_progress` threshold (plus a
    # buffer) and, once agent-config sync manages it, the ElevenLabs
    # `conversation.max_duration_seconds` platform setting.
    def max_call_duration_minutes
      ENV.fetch('AI_VOICE_MAX_CALL_DURATION_MINUTES', 15).to_i
    end

    private

    def flag(env_var)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(env_var, 'false'))
    end
  end
end
