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

    private

    def flag(env_var)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(env_var, 'false'))
    end
  end
end
