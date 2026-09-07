# frozen_string_literal: true

module Api
  module V1
    module Admin
      module Payments
        # Applies a manual correction to a payment record (e.g. fixing a
        # reconciliation finding), on top of the read-only PaymentsController.
        class CorrectionsController < ProtectedStaffController
          # Applies a correction to the given payment and returns the
          # updated payment detail; deduplicated via the idempotency
          # fingerprint so a retried request does not apply it twice.
          def create
            authorize payment, :create_correction?, policy_class: ::Admin::PaymentPolicy

            render_idempotent_response(
              scope: 'admin.payments.corrections.create',
              subject: current_user,
              fingerprint: correction_fingerprint,
              required: true
            ) { correction_payload }
          end

          private

          # Loads the payment named in the route, raising if no payment
          # matches the given public id.
          def payment
            @payment ||= ::Payment.find_by(public_id: params.expect(:payment_id)).tap do |record|
              raise PaymentNotFoundError if record.blank?
            end
          end

          # Executes the correction via CorrectionService, guarded by an
          # optimistic-concurrency check, and serializes the reloaded
          # payment for the response.
          def correction_payload
            corrected = ::Admin::Payments::CorrectionService.call(
              actor: current_user,
              payment:,
              request_id: request.request_id,
              **correction_params
            )
            set_private_state_headers(updated_at: corrected.updated_at, etag_key: corrected.public_id)
            success_payload(data: ::Admin::Payments::PaymentDetailSerializer.new(corrected.reload).as_json,
                            status: :created)
          end

          # Permits the correction params: reason, the expected current
          # timestamp, the reconciliation finding being addressed, and the
          # field/value being corrected.
          def correction_params
            params.expect(correction: %i[reason expected_updated_at finding_id field value]).to_h.symbolize_keys
          end

          # Builds the idempotency-key fingerprint for this correction
          # request.
          def correction_fingerprint
            { payment_id: payment.public_id }.merge(correction_params).to_json
          end
        end
      end
    end
  end
end
