# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Exposes KuickPay onboarding-fee payment records for admin review:
      # a filtered, paginated list and a single payment's full detail.
      class PaymentsController < ProtectedStaffController
        # Returns a paginated, filtered list of payments with reconciliation
        # findings preloaded to avoid N+1 queries.
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

        # Returns full detail for a single payment, including its
        # assignment, actor history and reconciliation findings.
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

        # Scopes the payment table to what the current staff member is
        # authorized to view.
        def payment_scope
          policy_scope(::Payment, policy_scope_class: ::Admin::PaymentPolicy::Scope)
        end

        # Loads the requested payment with its detail associations
        # preloaded, raising if no payment matches the given public id.
        def payment
          @payment ||= begin
            record = ::Payment.preload(detail_preloads).find_by(public_id: params.expect(:id))
            raise PaymentNotFoundError if record.blank?

            record
          end
        end

        # Associations needed to render the payment detail view without
        # triggering N+1 queries.
        def detail_preloads
          { candidate_assignment: :candidate, payment_events: :actor, payment_reconciliation_findings: :resolved_by }
        end

        # Sets the private cache/ETag headers for a single payment's detail
        # response.
        def apply_payment_state_headers(record)
          set_private_state_headers(updated_at: record.updated_at, etag_key: record.public_id)
        end
      end
    end
  end
end
