# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the Admin dashboard (MPS-801): candidate workload,
    # document-review queue depth, workflow-stage queues, payment
    # visibility. Every section is already-built report/queue query
    # output; this service only decides what belongs on this particular
    # dashboard.
    class AdminSummaryService < ApplicationService
      def call
        {
          candidate_workload: { total_active_candidates: Candidate.active.count },
          workflow_stage_queue: Reports::StatusSummaryQuery.call,
          document_review_queue: document_review_summary,
          payment_summary: Reports::PaymentSummaryQuery.call
        }
      end

      private

      def document_review_summary
        DocumentReviewQueueQuery.new(scope: CandidateDocumentSubmission.all, params: ActionController::Parameters.new).summary
      end
    end
  end
end
