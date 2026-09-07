# frozen_string_literal: true

module Sms
  # Reads every SMS-provider-related setting from ENV, mirroring
  # Payments::Configuration's exact pattern -- one place that knows the env
  # var names, so providers themselves never touch ENV directly.
  class Configuration
    def sendpk_api_key
      ENV['SENDPK_API_KEY'].to_s.strip.presence
    end

    def sendpk_sender_id
      ENV['SENDPK_SENDER_ID'].to_s.strip.presence
    end

    def sendpk_base_url
      ENV.fetch('SENDPK_BASE_URL', 'https://sendpk.com').strip
    end

    def sendpk_open_timeout
      ENV.fetch('SENDPK_OPEN_TIMEOUT_SECONDS', 5).to_i
    end

    def sendpk_read_timeout
      ENV.fetch('SENDPK_READ_TIMEOUT_SECONDS', 10).to_i
    end
  end
end
