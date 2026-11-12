# frozen_string_literal: true

module Payments
  # Queued when a candidate enters the fee stage (CandidateWorkflows::TransitionSideEffectRecorder). Only ids are
  # in the arguments. A KuickPay outage is retried a few times; after that the candidate can still get their
  # code from the app's payment screen, and no fee SMS claims one was sent.
  class IssueFeeVoucherJob < ApplicationJob
    queue_as :default

    retry_on PaymentCheckoutUnavailableError, wait: 5.minutes, attempts: 5 do |job, _error|
      Rails.logger.warn(
        "Fee voucher not issued after retries: candidate_assignment_id=#{job.arguments.first[:candidate_assignment_id]}"
      )
    end

    def perform(candidate_assignment_id:, history_entry_id:)
      Payments::IssueFeeVoucherService.call(candidate_assignment_id:, history_entry_id:)
    end
  end
end
