# frozen_string_literal: true

module Admin
  module DocumentReviews
    DecisionResult = Data.define(:document, :submission, :summary)
  end
end
