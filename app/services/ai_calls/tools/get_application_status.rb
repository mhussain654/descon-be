# frozen_string_literal: true

module AiCalls
  module Tools
    class GetApplicationStatus < VerifiedDataTool
      private

      def data
        progress = ::Candidates::ApplicationProgress::SummaryService.call(candidate:, assignment:)
        {
          candidate_status: progress.candidate_status,
          current_stage: progress.current_workflow_stage&.code,
          completed_count: progress.workflow_completed_count,
          total_count: progress.workflow_total_count,
          progress_percentage: progress.workflow_progress_percentage
        }
      end
    end
  end
end
