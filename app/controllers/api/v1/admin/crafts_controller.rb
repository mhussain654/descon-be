# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Manages the craft/trade reference list used for candidate skill classification,
      # including whether a craft is a driver craft (`is_driver`) -- the backend uses that
      # flag to decide driver-only document requirements such as the Qatar driving licence.
      class CraftsController < ReferenceDataController
        private

        # Tells the shared reference-data controller which model backs this endpoint.
        def record_class = ::Craft

        def extra_param_keys = %i[is_driver]

        def extra_attributes(record) = { is_driver: record.is_driver }
      end
    end
  end
end
