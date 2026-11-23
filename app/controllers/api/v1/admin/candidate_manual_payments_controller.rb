# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets a developer mark a candidate's fee paid when KuickPay took the
      # money but the system never recorded it (Admin::Payments::ManualPaymentService).
      class CandidateManualPaymentsController < ProtectedStaffController
        def create
          authorize ::Payment, :record_manual?, policy_class: ::Admin::PaymentPolicy

          payment = ::Admin::Payments::ManualPaymentService.call(
            actor: current_user, candidate:, request_id: request.request_id, values: manual_payment_params
          )
          render_success(data: ::Admin::Payments::PaymentSummarySerializer.new(payment.reload).as_json,
                         status: :created)
        end

        private

        def manual_payment_params
          params.expect(manual_payment: %i[reference paid_on reason]).to_h.symbolize_keys
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end
      end
    end
  end
end
