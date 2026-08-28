# frozen_string_literal: true

module Admin
  class DocumentReviewSummarySerializer
    def initialize(summary)
      @summary = summary
    end

    def as_json(*)
      {
        pending_review: @summary.pending_review,
        verified: @summary.verified,
        rejected: @summary.rejected,
        required_total: @summary.required_total,
        review_state: @summary.review_state
      }
    end
  end
end
