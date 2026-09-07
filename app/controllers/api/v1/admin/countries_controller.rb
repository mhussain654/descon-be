# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Exposes the read-only country reference list used for candidate destination selection.
      class CountriesController < ReferenceDataController
        private

        # Tells the shared reference-data controller which model backs this endpoint.
        def record_class = ::Country
      end
    end
  end
end
