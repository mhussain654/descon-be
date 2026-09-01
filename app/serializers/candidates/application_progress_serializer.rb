# frozen_string_literal: true

module Candidates
  class ApplicationProgressSerializer
    def initialize(progress)
      @progress = progress
    end

    def as_json(*)
      {
        candidate_status: @progress.candidate_status,
        current_workflow_stage: serialized_workflow_stage,
        workflow: serialized_workflow,
        documents: serialized_documents,
        payment: serialized_payment
      }
    end

    private

    def serialized_blocking_requirements
      @progress.documents.blocking_requirements.map do |requirement|
        {
          requirement_code: requirement.requirement_code,
          name: requirement.name,
          reason: requirement.reason
        }
      end
    end

    def serialized_documents
      document_counts.merge(
        can_submit: @progress.documents.can_submit,
        submission_state: @progress.documents.submission_state,
        blocking_requirements: serialized_blocking_requirements
      )
    end

    def serialized_workflow
      {
        timeline: @progress.workflow_timeline,
        completed_count: @progress.workflow_completed_count,
        total_count: @progress.workflow_total_count,
        progress_percentage: @progress.workflow_progress_percentage,
        updated_at: @progress.workflow_updated_at
      }
    end

    def serialized_workflow_stage
      stage = @progress.current_workflow_stage
      return if stage.blank?

      {
        code: stage.code,
        name: stage.name_for
      }
    end

    def document_counts
      {
        required_total: @progress.documents.required_total,
        missing: @progress.documents.missing,
        uploaded: @progress.documents.uploaded,
        pending_review: @progress.documents.pending_review,
        verified: @progress.documents.verified,
        rejected: @progress.documents.rejected,
        submitted_total: @progress.documents.submitted_total,
        completion_percentage: @progress.documents.completion_percentage
      }
    end

    def serialized_payment
      Payments::EligibilitySerializer.new(Payments::EligibilityService.call(candidate: @progress.candidate)).as_json
    end
  end
end
