# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CraftsController < ProtectedStaffController
        def index
          authorize :reference_data, :index?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: crafts.order(:code).map { |record| serialized(record) })
        end

        private

        def crafts
          policy_scope(::Craft, policy_scope_class: ::Admin::ReferenceDataPolicy::Scope)
        end

        def serialized(record)
          { code: record.code, name: record.name_for }
        end
      end
    end
  end
end
