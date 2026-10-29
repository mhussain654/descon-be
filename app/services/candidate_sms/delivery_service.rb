# frozen_string_literal: true

module CandidateSms
  # Sends one queued progress SMS through Sms::SendMessage and records the
  # outcome on its CandidateSmsDelivery. Only a pending delivery is sent, so a
  # repeated job never sends twice. A message whose template is not set up yet
  # is skipped, not failed; a network-level failure raises RetryableError for
  # CandidateSms::DeliveryJob to retry.
  class DeliveryService < ApplicationService
    class RetryableError < StandardError; end

    RETRYABLE_ERROR_CODES = %w[timeout network_error http_error].freeze

    def initialize(candidate_sms_delivery_id:)
      @delivery_id = candidate_sms_delivery_id
    end

    def call
      CandidateSmsDelivery.transaction do
        delivery = CandidateSmsDelivery.lock.find_by(id: @delivery_id)
        next if delivery.blank? || !delivery.pending?
        next finish!(delivery, status: 'skipped', error_code: 'candidate_inactive') unless delivery.candidate.active?

        record_result!(delivery, send_message(delivery))
      end
    end

    private

    def send_message(delivery)
      Sms::SendMessage.call(
        to: delivery.candidate.mobile_number, body: body_for(delivery), variables: delivery.variables,
        template: delivery.message_code, locale: delivery.locale
      )
    end

    def body_for(delivery)
      I18n.t("candidate_sms.#{delivery.message_code}", locale: delivery.locale,
                                                       **delivery.variables.symbolize_keys)
    end

    def record_result!(delivery, result)
      if result.success?
        finish!(delivery, status: 'sent', provider_reference: result.provider_reference, sent_at: Time.current)
      elsif result.error_code == 'not_configured'
        finish!(delivery, status: 'skipped', error_code: result.error_code)
      elsif RETRYABLE_ERROR_CODES.include?(result.error_code)
        raise RetryableError, result.error_code
      else
        finish!(delivery, status: 'failed', error_code: result.error_code)
      end
    end

    def finish!(delivery, **attributes)
      delivery.update!(attributes)
    end
  end
end
