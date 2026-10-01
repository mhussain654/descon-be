# frozen_string_literal: true

module Sms
  # Reads every SMS-provider-related setting from config/sendpk.yml (secrets
  # from encrypted credentials, the rest from ENV), so providers themselves
  # never touch ENV or credentials directly.
  class Configuration
    def sendpk_api_key
      setting(:api_key)
    end

    def sendpk_sender_id
      setting(:sender_id)
    end

    # The Urdu template (template_id_ur) is used for Urdu locales when it is
    # set; every other locale, or an unset Urdu id, uses the English one.
    def sendpk_template_id(locale = nil)
      urdu = setting(:template_id_ur) if locale.to_s == 'ur'
      urdu || setting(:template_id)
    end

    def sendpk_base_url
      setting(:base_url) || 'https://sendpk.com'
    end

    def sendpk_open_timeout
      setting(:open_timeout).to_i
    end

    def sendpk_read_timeout
      setting(:read_timeout).to_i
    end

    private

    def setting(key)
      @settings ||= Rails.application.config_for(:sendpk)
      @settings[key].to_s.strip.presence
    end
  end
end
