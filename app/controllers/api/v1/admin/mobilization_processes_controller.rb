# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Developer-only, read-only view of the active and draft mobilization
      # processes (common and per country) with their ordered stages.
      class MobilizationProcessesController < ProtectedStaffController
        def index
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          processes = policy_scope(MobilizationProcess, policy_scope_class: ::Admin::ReferenceDataPolicy::ManagedScope)
                      .where(status: %w[active draft])
                      .includes(:country, stages: :workflow_stage)
                      .order(Arel.sql('country_id IS NOT NULL'), :code, version: :desc)
          render_success(data: processes.map { |process| ::Admin::MobilizationProcessSerializer.new(process).as_json })
        end
      end
    end
  end
end
