# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CountriesController < ProtectedStaffController
        def index
          authorize :reference_data, :index?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: countries.order(:code).map { |record| serialized(record) })
        end

        private

        def countries
          policy_scope(::Country, policy_scope_class: ::Admin::ReferenceDataPolicy::Scope)
        end

        def serialized(record)
          { code: record.code, name: record.name_for }
        end
      end
    end
  end
end
