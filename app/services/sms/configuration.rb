# frozen_string_literal: true

module Sms
  # Reads every SMS-provider-related setting -- the account from
  # config/sendpk.yml (secrets from encrypted credentials, the rest from ENV),
  # each message's template ids from its SmsTemplate row -- so providers
  # themselves never touch ENV, credentials or App Settings directly.
  class Configuration
    def sendpk_api_key
      setting(:api_key)
    end

    # The login code (OTP) goes out from the short code; every other message
    # from the brand name.
    def sendpk_sender_id(template = nil)
      template.to_s == 'otp' ? setting(:otp_sender_id) : setting(:sms_sender_id)
    end

    # Each message (`template`, e.g. :otp or :registered) has its own approved
    # template: the Urdu one is used for Urdu locales when it is set; every
    # other locale, or an unset Urdu id, uses the English one.
    def sendpk_template_id(template, locale = nil)
      sendpk_urdu_template_id(template, locale) || sms_template(template)&.template_id_en
    end

    # The Urdu template id when one applies, so the provider knows to send Unicode.
    def sendpk_urdu_template_id(template, locale)
      sms_template(template)&.template_id_ur if locale.to_s == 'ur'
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

    def sms_template(template)
      code = template.to_s
      @sms_templates ||= {}
      @sms_templates.fetch(code) { @sms_templates[code] = SmsTemplate.find_for(code) }
    end

    def setting(key)
      @settings ||= Rails.application.config_for(:sendpk)
      @settings[key].to_s.strip.presence
    end
  end
end
