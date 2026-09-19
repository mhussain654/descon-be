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
      def initialize(params: ActionController::Parameters.new)
        super()
        @params = params
      end

      def call
        scope = filtered_scope
        sections = base_sections(scope).merge(
          document_review_queue: document_review_summary(scope),
          payment_summary: Reports::PaymentSummaryQuery.call(scope:)
        )
        sections.merge(requires_attention: requires_attention(sections:, pending_actions: Reports::PendingActionsQuery.call(scope:)))
      end

      private

      def filtered_scope
        Reports::DashboardFilterResolution.call(params: @params)
      end

      def base_sections(scope)
        {
          candidate_workload: { total_active_candidates: scope.active.count },
          workflow_stage_queue: Reports::StatusSummaryQuery.call(scope:),
          conversion_funnel: Reports::ConversionQuery.call(scope:),
          average_stage_duration_days: Reports::AverageStageDurationQuery.call(scope:),
          upcoming_activities: Reports::UpcomingActivitiesQuery.call(scope:),
          recently_updated_candidates: Reports::RecentlyUpdatedCandidatesQuery.call(scope:),
          kpi_trends: Reports::KpiTrendQuery.call(scope:)
        }
      end

      # Scoped by the same filtered candidate set as every other section --
      # constrained via candidate_assignment_id rather than passed through
      # DocumentReviewQueueQuery's own separate country_code/project_code
      # filter params, so this one query stays the single source of truth
      # for what "matches the requested filters" means (that params-based
      # path also has no craft_code support and doesn't validate an unknown
      # code the way DashboardFilterResolution does).
      def document_review_summary(scope)
        assignment_ids = Reports::CurrentAssignmentJoin.call(scope:).select('current_assignments.id')
        DocumentReviewQueueQuery.new(
          scope: CandidateDocumentSubmission.where(candidate_assignment_id: assignment_ids),
          params: ActionController::Parameters.new
        ).summary
      end

      def requires_attention(sections:, pending_actions:)
        failed_payment_count = sections.fetch(:payment_summary).find do |row|
          row.fetch(:code) == 'failed'
        end&.fetch(:count) || 0

        [
          { code: 'rejected_documents', count: sections.fetch(:document_review_queue).fetch('rejected') },
          { code: 'failed_payment', count: failed_payment_count },
          { code: 'overdue_qvc', count: pending_actions.fetch(:overdue_qvc_count) },
          { code: 'callback_required', count: pending_actions.fetch(:callback_required_count) }
        ]
      end
    end
  end
end
