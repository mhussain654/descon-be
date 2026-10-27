# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Gives the candidate a payment code (KuickPay voucher number) for their fee,
      # to pay from a wallet or bank app -- the alternative to the card checkout in
      # PaymentsController. Needs an Idempotency-Key, like the card checkout.
      class PaymentVouchersController < ProtectedController
        # Creates the voucher, or returns the one that is still open.
        def create
          authorize current_candidate, policy_class: ::Candidates::PaymentPolicy

          render_idempotent_response(scope: 'candidate.payment_vouchers.create', subject: current_candidate,
                                     fingerprint: fingerprint, required: true) { create_voucher_payload }
        end

        private

        def create_voucher_payload
          result = ::Payments::CreateVoucherService.call(candidate: current_candidate, request_id: request.request_id)
          set_private_state_headers(updated_at: current_candidate.current_assignment&.reload&.updated_at,
                                    etag_key: "#{current_candidate.public_id}:payment")
          success_payload(data: response_payload(result), status: :created)
        end

        def fingerprint
          { candidate_public_id: current_candidate.public_id, method: 'voucher' }.to_json
        end

        def response_payload(result)
          {
            eligibility: ::Payments::EligibilitySerializer.new(result.fetch(:eligibility)).as_json,
            payment: ::Payments::PaymentSerializer.new(result.fetch(:payment)).as_json
          }
        end
      end
    end
  end
end
