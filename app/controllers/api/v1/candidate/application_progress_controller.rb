# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view an overall summary of their application's progress through the recruitment workflow.
      class ApplicationProgressController < ProtectedController
        # Returns a summary of the current candidate's application progress, with cache/ETag
        # headers reflecting the assignment's last update time.
        def show
          authorize current_candidate, policy_class: ::Candidates::ApplicationProgressPolicy

          progress = ::Candidates::ApplicationProgress::SummaryService.call(candidate: current_candidate)
          set_private_state_headers(
            updated_at: current_candidate.current_assignment&.updated_at,
            etag_key: "#{current_candidate.public_id}:application_progress"
          )
          render_success(data: ::Candidates::ApplicationProgressSerializer.new(progress).as_json)
        end
      end
    end
  end
end
