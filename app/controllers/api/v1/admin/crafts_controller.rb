# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CraftsController < ReferenceDataController
        private

        def record_class = ::Craft
      end
    end
  end
end
