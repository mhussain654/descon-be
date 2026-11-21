# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    class WorkflowSummaryBuilder < ApplicationService
      def initialize(candidate:, assignment:, current_documents_by_type:, requirements:)
        @candidate = candidate
        @assignment = assignment
        @current_documents_by_type = current_documents_by_type
        @requirements = requirements
      end

      def call
        Summary.new(**summary_attributes)
      end

      private

      def summary_attributes
        snapshot = workflow_snapshot

        base_summary_attributes.merge(workflow_summary_attributes(snapshot))
      end

      def base_summary_attributes
        {
          candidate: @candidate,
          candidate_status: @candidate.status_code,
          current_workflow_stage: @assignment&.current_workflow_stage,
          documents: documents_summary
        }
      end

      def workflow_summary_attributes(snapshot)
        {
          workflow_mobilization_process: snapshot.mobilization_process,
          workflow_timeline: snapshot.timeline,
          workflow_completed_count: snapshot.completed_count,
          workflow_total_count: snapshot.total_count,
          workflow_progress_percentage: snapshot.progress_percentage,
          workflow_updated_at: snapshot.updated_at,
          workflow_outcomes: outcomes
        }
      end

      # The latest medical result and visa decision, so the candidate's journey
      # can show a step as Rejected (unfit, visa refused) and not only as done,
      # and whether the boarding pass is uploaded (and not rejected by staff),
      # which completes Mobilize Status.
      def outcomes
        return { medical: nil, visa: nil, boarding_pass: nil } if @assignment.blank?

        {
          medical: @assignment.candidate_medical_results.order(:id).last&.outcome_code,
          visa: @assignment.candidate_visa_decisions.order(:id).last&.outcome_code,
          boarding_pass: boarding_pass_accepted? ? 'uploaded' : nil
        }
      end

      def boarding_pass_accepted?
        detail = @assignment.candidate_flight_detail
        detail.present? && detail.boarding_pass_uploaded? && !detail.boarding_pass_rejected?
      end

      def documents_summary
        @documents_summary ||= DocumentSummaryBuilder.call(
          assignment: @assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        )
      end

      def workflow_snapshot
        @workflow_snapshot ||= CandidateWorkflows::StateSnapshotService.call(candidate: @candidate)
      end
    end
  end
end
