# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class ResultBuilder < ApplicationService
      def initialize(progress:, submission:)
        @progress = progress
        @submission = submission
      end

      def call
        Result.new(
          submission_id: @submission.public_id,
          submission_state: @progress.documents.submission_state,
          submitted_at: @submission.submitted_at.utc.iso8601,
          documents: {
            required_total: @progress.documents.required_total,
            pending_review: @progress.documents.pending_review,
            can_submit: @progress.documents.can_submit
          }
        )
      end
    end
  end
end
