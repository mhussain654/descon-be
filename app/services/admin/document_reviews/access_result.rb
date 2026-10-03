# frozen_string_literal: true

module Admin
  module DocumentReviews
    AccessResult = Data.define(:document, :file, :expires_at, :url)
  end
end
