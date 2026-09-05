# frozen_string_literal: true

module Admin
  module Reports
    # Rejected / re-medical / no-show tracking (MPS-804) -- surfaces
    # negative-outcome counts that are otherwise only visible one record at
    # a time in the document-review queue or a candidate's own workflow
    # panels. Every count is a simple, direct aggregation over
    # already-recorded data; nothing here infers or reclassifies an
    # outcome.
    class OutcomeTrackingQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        {
          rejected_documents: rejected_documents_count,
          qvc_re_medical: qvc_attempts_count(outcome_code: 're_medical'),
          qvc_rejected: qvc_attempts_count(outcome_code: 'rejected'),
          qvc_no_show: qvc_no_show_count,
          visa_rejected: visa_decisions_count(outcome_code: 'rejected')
        }
      end

      private

      def assignment_ids
        @assignment_ids ||= CurrentAssignmentJoin.call(scope: @scope).pluck('current_assignments.id')
      end

      def rejected_documents_count
        CandidateDocument.current_version.where(candidate_assignment_id: assignment_ids, status_code: 'rejected').count
      end

      def qvc_attempts_count(outcome_code:)
        CandidateQvcAttempt.where(candidate_assignment_id: assignment_ids, outcome_code:).count
      end

      def qvc_no_show_count
        CandidateQvcAttempt.where(candidate_assignment_id: assignment_ids, no_show: true).count
      end

      def visa_decisions_count(outcome_code:)
        CandidateVisaDecision.where(candidate_assignment_id: assignment_ids, outcome_code:).count
      end
    end
  end
end
