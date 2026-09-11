# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the per-workflow-stage AI call scripts
      # (AiCalls::TriggerWorkflowStageCallService's content source).
      # Deliberately index+update only -- the row set is fixed to
      # WorkflowStage::CANONICAL_STAGES and seeded up front, so there is no
      # create/destroy route: admin edits an existing stage's script, never
      # adds or removes a stage.
      class WorkflowStageCallScriptsController < ProtectedStaffController
        UPDATE_PARAMS = %i[announcement active language_code].freeze

        def index
          authorize ::WorkflowStageCallScript, policy_class: ::Admin::WorkflowStageCallScriptPolicy

          render_success(data: indexed_scripts.map { |script| serialized(script) })
        end

        def update
          authorize ::WorkflowStageCallScript, policy_class: ::Admin::WorkflowStageCallScriptPolicy

          script = update_script!
          render_success(data: serialized(script))
        end

        private

        def indexed_scripts
          script_scope.includes(:updated_by).order(:workflow_stage_code)
        end

        def script_scope
          policy_scope(::WorkflowStageCallScript, policy_scope_class: ::Admin::WorkflowStageCallScriptPolicy::Scope)
        end

        def script
          @script ||= script_scope.find_by!(workflow_stage_code: params.expect(:workflow_stage_code))
        end

        def update_script!
          ::WorkflowStageCallScript.transaction do
            record = script.lock!
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(workflow_stage_call_script: UPDATE_PARAMS)
        end

        def record_audit!(record)
          ::AuditEvent.create!(
            actor: current_user, entity_type: 'WorkflowStageCallScript', entity_id: record.id,
            action_code: 'workflow_stage_call_script_updated', request_id: request.request_id,
            occurred_at: Time.current,
            metadata: { workflow_stage_code: record.workflow_stage_code, active: record.active }
          )
        end

        def serialized(record)
          ::Admin::WorkflowStageCallScripts::WorkflowStageCallScriptSerializer.new(record).as_json
        end
      end
    end
  end
end
