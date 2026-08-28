# frozen_string_literal: true

module Admin
  module DocumentReviews
    AccessResult = Data.define(:document, :expires_at, :url)
  end
end
