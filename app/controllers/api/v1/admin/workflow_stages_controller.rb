# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Developer-only workflow stage names: every stage with its built-in
      # names and any name set in admin, and setting or clearing those names.
      class WorkflowStagesController < ProtectedStaffController
        def index
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          stages = policy_scope(WorkflowStage, policy_scope_class: ::Admin::ReferenceDataPolicy::ManagedScope)
          render_success(data: stages.order(:position).map { |stage| serialized(stage) })
        end

        def update
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          names = params.fetch(:workflow_stage, {}).permit(:name_en, :name_ur)
          stage = ::Admin::WorkflowStages::RenameService.call(
            actor: current_user,
            stage: WorkflowStage.find_by!(code: params.expect(:code)),
            name_en: names[:name_en],
            name_ur: names[:name_ur],
            request_id: request.request_id
          )
          render_success(data: serialized(stage))
        end

        private

        def serialized(stage)
          {
            code: stage.code,
            position: stage.position,
            name: stage.name_for,
            default_name_en: stage.default_name_for(locale: :en),
            default_name_ur: stage.default_name_for(locale: :ur),
            name_en: stage.name_en,
            name_ur: stage.name_ur
          }
        end
      end
    end
  end
end
