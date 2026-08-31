# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class PaymentsController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::PaymentPolicy

          eligibility = ::Payments::EligibilityService.call(candidate: current_candidate)
          apply_state_headers(eligibility.assignment)
          render_success(data: ::Payments::EligibilitySerializer.new(eligibility).as_json)
        end

        def create
          authorize current_candidate, policy_class: ::Candidates::PaymentPolicy

          render_idempotent_response(**idempotency_options) { create_checkout_payload }
        end

        private

        def create_checkout_payload
          result = ::Payments::CheckoutSessionService.call(
            candidate: current_candidate,
            request_id: request.request_id
          )
          apply_state_headers(current_candidate.current_assignment&.reload)
          success_payload(data: response_payload(result), status: :created)
        end

        def idempotency_options
          {
            scope: 'candidate.payments.create',
            subject: current_candidate,
            fingerprint: payment_fingerprint,
            required: true
          }
        end

        def payment_fingerprint
          configuration = ::Payments::Configuration.new

          {
            candidate_public_id: current_candidate.public_id,
            amount: configuration.amount.to_s('F'),
            currency_code: configuration.currency_code,
            provider_code: configuration.provider_code
          }.to_json
        end

        def response_payload(result)
          {
            eligibility: ::Payments::EligibilitySerializer.new(result.fetch(:eligibility)).as_json,
            payment: ::Payments::PaymentSerializer.new(result.fetch(:payment)).as_json
          }
        end

        def apply_state_headers(assignment)
          set_private_state_headers(
            updated_at: assignment&.updated_at,
            etag_key: "#{current_candidate.public_id}:payment"
          )
        end
      end
    end
  end
end
