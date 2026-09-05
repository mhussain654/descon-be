# frozen_string_literal: true

module Admin
  module Reports
    # Payment-status counts for current assignments (MPS-801's "payment
    # visibility" dashboard tile). Every status is represented, zero-filled,
    # same convention as StatusSummaryQuery.
    class PaymentSummaryQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        counts = counts_by_status
        Payment::STATUS_CODES.map { |code| { code:, count: counts.fetch(code, 0) } }
      end

      private

      def counts_by_status
        assignment_ids = CurrentAssignmentJoin.call(scope: @scope).pluck('current_assignments.id')
        Payment.where(candidate_assignment_id: assignment_ids).group(:status_code).count
      end
    end
  end
end
