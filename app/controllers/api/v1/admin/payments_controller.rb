# frozen_string_literal: true

module Api
  module V1
    module Admin
      class PaymentsController < ProtectedStaffController
        def index
          authorize ::Payment, policy_class: ::Admin::PaymentPolicy

          query = ::Admin::Payments::IndexQuery.new(scope: payment_scope, params:)
          payments = query.call.includes(:payment_reconciliation_findings)

          render_collection(
            data: payments.map { |payment| ::Admin::Payments::PaymentSummarySerializer.new(payment).as_json },
            pagination: query.pagination,
            meta: { applied_filters: query.applied_filters }
          )
        end

        def show
          # Admin::PaymentPolicy#show? never inspects the record (permission-
          # only), so authorize against the class first -- a forbidden staff
          # member never triggers the detail preload below at all.
          authorize ::Payment, :show?, policy_class: ::Admin::PaymentPolicy

          record = payment
          apply_payment_state_headers(record)
          render_success(data: ::Admin::Payments::PaymentDetailSerializer.new(record).as_json)
        end

        private

        def payment_scope
          policy_scope(::Payment, policy_scope_class: ::Admin::PaymentPolicy::Scope)
        end

        def payment
          @payment ||= begin
            record = ::Payment.preload(detail_preloads).find_by(public_id: params.expect(:id))
            raise PaymentNotFoundError if record.blank?

            record
          end
        end

        def detail_preloads
          { candidate_assignment: :candidate, payment_events: :actor, payment_reconciliation_findings: :resolved_by }
        end

        def apply_payment_state_headers(record)
          set_private_state_headers(updated_at: record.updated_at, etag_key: record.public_id)
        end
      end
    end
  end
end
