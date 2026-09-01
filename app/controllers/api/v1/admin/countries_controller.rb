# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CountriesController < ReferenceDataController
        private

        def record_class = ::Country
      end
    end
  end
end
