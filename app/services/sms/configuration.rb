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

    # Zong numbers (0310-0319, i.e. 92 31x) while Zong has not approved the
    # mask. Numbers ported from another network keep their old prefix, so
    # they are picked by the number they had, not the network they are on.
    ZONG_NUMBER = /\A(?:92|0)31\d/

    # The login code (OTP) goes out from its sender; every other message from
    # the brand name. Zong has not approved the "DESCON MPS" mask yet, so a
    # Zong number gets the short code instead while `zong_sender_id` is set;
    # once Zong approves the mask, clearing that setting sends to Zong from
    # the mask like every other network.
    def sendpk_sender_id(template = nil, to: nil)
      zong_sender = setting(:zong_sender_id) if zong_number?(to)
      return zong_sender if zong_sender

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

    def zong_number?(to)
      to.to_s.gsub(/\D/, '').match?(ZONG_NUMBER)
    end

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
