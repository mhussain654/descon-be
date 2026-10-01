# frozen_string_literal: true

module Admin
  module Reports
    # The two "requires attention" counts that don't already exist elsewhere
    # in the dashboard response (admin dashboard redesign). Rejected
    # documents and failed payments are already computed by
    # document_review_queue/payment_summary -- Admin::Dashboards::
    # AdminSummaryService assembles the final requires_attention list from
    # those plus this query's output, rather than recomputing them here.
    class PendingActionsQuery < ApplicationQuery
      CALLBACK_LOOKBACK = 30.days

      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        { overdue_qvc_count: overdue_qvc_count, callback_required_count: callback_required_count }
      end

      private

      def overdue_qvc_count
        CandidateQvcAttempt.open_attempts
                           .where(candidate_assignment_id: assignment_ids)
                           .where(appointment_date: ...Date.current)
                           .count
      end

      # CandidateAiCall has no "resolved"/"handled" flag for a
      # callback_required outcome (unlike needs_manual_review, which has
      # reviewed_at) -- every call ever marked callback_required would stay
      # in an unscoped count forever. Scoped to the last 30 days so the
      # number reflects recent, plausibly-still-relevant callbacks rather
      # than growing unbounded; this is a known, documented gap (there is no
      # way today to mark a callback as actioned), not a hidden assumption.
      def callback_required_count
        CandidateAiCall.where(outcome: 'callback_required', candidate_id: candidate_ids)
                       .where(completed_at: CALLBACK_LOOKBACK.ago..)
                       .count
      end

      def assignment_ids
        @assignment_ids ||= CurrentAssignmentJoin.call(scope: @scope).select('current_assignments.id')
      end

      def candidate_ids
        @candidate_ids ||= @scope.select(:id)
      end
    end
  end
end
