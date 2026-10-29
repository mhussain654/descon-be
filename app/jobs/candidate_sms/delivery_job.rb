# frozen_string_literal: true

module CandidateSms
  # Sends one progress SMS queued by CandidateSms::ScheduleDelivery. Only the
  # delivery's id is in the job arguments; the phone number and message values
  # stay in the database. A network-level failure is retried a few times, then
  # the delivery is marked failed with the last error.
  class DeliveryJob < ApplicationJob
    queue_as :default

    retry_on DeliveryService::RetryableError, wait: 5.minutes, attempts: 5 do |job, error|
      CandidateSmsDelivery.where(id: job.arguments.first[:candidate_sms_delivery_id], status: 'pending')
                          .update_all(status: 'failed', error_code: error.message, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def perform(candidate_sms_delivery_id:)
      DeliveryService.call(candidate_sms_delivery_id:)
    end
  end
end
