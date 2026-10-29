# frozen_string_literal: true

module Admin
  module AppFeatureSettings
    # Whether the server is set up (env vars, credentials) for each switchable
    # feature, regardless of its App Settings switch. Reads the same checks the
    # features themselves use, so the admin page never disagrees with them.
    class ServerReadiness
      def as_json(*)
        {
          card_payment: provider_available?('kuickpay'),
          voucher_payment: provider_available?('kuickpay_voucher'),
          progress_sms: sendpk_ready?,
          automatic_calls: ai_calls.outbound_enabled?,
          bulk_calls: ai_calls.outbound_enabled? && ai_calls.robocall?,
          document_ocr: ::DocumentOcr::TextractAdapter.enabled?
        }
      end

      # The message's English template id is set (the Urdu one is optional).
      def sms_template_ready?(message_code)
        sms_configuration.sendpk_template_id(message_code).present?
      end

      private

      def provider_available?(provider_code)
        ::Payments::ProviderRegistry.fetch(provider_code).available?
      rescue ::Payments::ProviderNotConfiguredError
        false
      end

      def sendpk_ready?
        ENV.fetch('SMS_PROVIDER', 'test') == 'sendpk' && sms_configuration.sendpk_api_key.present? &&
          sms_configuration.sendpk_sender_id.present?
      end

      def ai_calls = @ai_calls ||= ::AiCalls::Configuration.new
      def sms_configuration = @sms_configuration ||= ::Sms::Configuration.new
    end
  end
end
