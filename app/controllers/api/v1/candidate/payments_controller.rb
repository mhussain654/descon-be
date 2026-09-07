# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate check their onboarding-fee payment eligibility/status and start a
      # KuickPay checkout session to pay it.
      class PaymentsController < ProtectedController
        # Returns whether the current candidate is eligible/required to pay, and their current payment status.
        def show
          authorize current_candidate, policy_class: ::Candidates::PaymentPolicy

          eligibility = ::Payments::EligibilityService.call(candidate: current_candidate)
          apply_state_headers(eligibility.assignment)
          render_success(data: ::Payments::EligibilitySerializer.new(eligibility).as_json)
        end

        # Starts a new payment checkout session with the payment provider; requires an
        # Idempotency-Key (fingerprinted on amount/currency/provider) so a retried request
        # can't create a duplicate checkout.
        def create
          authorize current_candidate, policy_class: ::Candidates::PaymentPolicy

          render_idempotent_response(**idempotency_options) { create_checkout_payload }
        end

        private

        # Creates the checkout session via the payment service and builds the created-payment success payload.
        def create_checkout_payload
          result = ::Payments::CheckoutSessionService.call(
            candidate: current_candidate,
            request_id: request.request_id
          )
          apply_state_headers(current_candidate.current_assignment&.reload)
          success_payload(data: response_payload(result), status: :created)
        end

        # Builds the idempotency options (scope, subject, fingerprint) passed to render_idempotent_response.
        def idempotency_options
          {
            scope: 'candidate.payments.create',
            subject: current_candidate,
            fingerprint: payment_fingerprint,
            required: true
          }
        end

        # Computes a fingerprint from the configured payment amount/currency/provider so a
        # replayed Idempotency-Key can be matched against the same intended charge.
        def payment_fingerprint
          configuration = ::Payments::Configuration.new

          {
            candidate_public_id: current_candidate.public_id,
            amount: configuration.amount.to_s('F'),
            currency_code: configuration.currency_code,
            provider_code: configuration.provider_code
          }.to_json
        end

        # Builds the response body combining updated eligibility and the created payment record.
        def response_payload(result)
          {
            eligibility: ::Payments::EligibilitySerializer.new(result.fetch(:eligibility)).as_json,
            payment: ::Payments::PaymentSerializer.new(result.fetch(:payment)).as_json
          }
        end

        # Sets cache/ETag headers for a payment-related response based on the assignment's last update time.
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
