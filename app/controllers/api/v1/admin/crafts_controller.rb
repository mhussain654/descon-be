# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Exposes the read-only craft/trade reference list used for candidate skill classification.
      class CraftsController < ReferenceDataController
        private

        # Tells the shared reference-data controller which model backs this endpoint.
        def record_class = ::Craft
      end
    end
  end
end
