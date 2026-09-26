# frozen_string_literal: true

module AiCalls
  module Tools
    class GetApplicationStatus < VerifiedDataTool
      private

      def data
        progress = ::Candidates::ApplicationProgress::SummaryService.call(candidate:, assignment:)
        {
          candidate_status: progress.candidate_status,
          current_stage_code: progress.current_workflow_stage&.code,
          current_stage_name: progress.current_workflow_stage&.name_for,
          next_stage_name: next_stage_name(progress),
          completed_count: progress.workflow_completed_count,
          total_count: progress.workflow_total_count,
          progress_percentage: progress.workflow_progress_percentage
        }
      end

      # `total_count`/`progress_percentage` count the 15 fixed internal pipeline
      # stages -- not meaningful read aloud to a candidate ("0 of 15" the moment
      # they register). `current_stage_name`/`next_stage_name` are the
      # human-readable equivalents the baseline prompt is expected to speak
      # instead; `current_stage_code` stays for the agent's own conditional
      # logic, never for narration.
      def next_stage_name(progress)
        progress.workflow_timeline.find { |stage| stage[:status] == 'pending' }&.fetch(:name)
      end
    end
  end
end
