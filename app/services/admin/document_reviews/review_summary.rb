# frozen_string_literal: true

module Admin
  module DocumentReviews
    ReviewSummary = Data.define(
      :pending_review,
      :rejected,
      :required_total,
      :review_state,
      :verified
    )
  end
end
