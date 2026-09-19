# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the Admin dashboard (MPS-801, extended by the admin
    # dashboard redesign): candidate workload, document-review queue depth,
    # workflow-stage queues, payment visibility, conversion/cycle-time
    # metrics, a cross-source "requires attention" list, upcoming QVC/flight
    # activity, recently-updated candidates, and per-KPI trend sparklines.
    # Every section is already-built report/queue query output; this
    # service only decides what belongs on this particular dashboard and
    # assembles requires_attention from sections computed elsewhere in this
    # same call rather than recomputing them.
    class AdminSummaryService < ApplicationService
      def call
        document_review_queue = document_review_summary
        payment_summary = Reports::PaymentSummaryQuery.call

        base_sections.merge(
          document_review_queue: document_review_queue,
          payment_summary: payment_summary,
          requires_attention: requires_attention(document_review_queue:, payment_summary:, pending_actions: Reports::PendingActionsQuery.call)
        )
      end

      private

      def base_sections
        {
          candidate_workload: { total_active_candidates: Candidate.active.count },
          workflow_stage_queue: Reports::StatusSummaryQuery.call,
          conversion_funnel: Reports::ConversionQuery.call,
          average_stage_duration_days: Reports::AverageStageDurationQuery.call,
          upcoming_activities: Reports::UpcomingActivitiesQuery.call,
          recently_updated_candidates: Reports::RecentlyUpdatedCandidatesQuery.call,
          kpi_trends: Reports::KpiTrendQuery.call
        }
      end

      def document_review_summary
        DocumentReviewQueueQuery.new(scope: CandidateDocumentSubmission.all, params: ActionController::Parameters.new).summary
      end

      def requires_attention(document_review_queue:, payment_summary:, pending_actions:)
        failed_payment_count = payment_summary.find { |row| row.fetch(:code) == 'failed' }&.fetch(:count) || 0

        [
          { code: 'rejected_documents', count: document_review_queue.fetch('rejected') },
          { code: 'failed_payment', count: failed_payment_count },
          { code: 'overdue_qvc', count: pending_actions.fetch(:overdue_qvc_count) },
          { code: 'callback_required', count: pending_actions.fetch(:callback_required_count) }
        ]
      end
    end
  end
end
