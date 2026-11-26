# frozen_string_literal: true

module Admin
  module WorkflowStages
    # Sets or clears a stage's display names (developer-only,
    # `manage_reference_data`). A blank name goes back to the built-in one.
    # The code, position and active flag never change here.
    class RenameService < ApplicationService
      def initialize(actor:, stage:, name_en:, name_ur:, request_id: nil)
        @actor = actor
        @stage = stage
        @name_en = name_en.to_s.strip.presence
        @name_ur = name_ur.to_s.strip.presence
        @request_id = request_id
      end

      def call
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('manage_reference_data')

        WorkflowStage.transaction do
          @stage.lock!
          @stage.update!(name_en: @name_en, name_ur: @name_ur)
          record_audit!
        end
        @stage
      end

      private

      def record_audit!
        AuditEvent.create!(
          actor: @actor,
          entity_type: 'WorkflowStage',
          entity_id: @stage.id,
          action_code: 'workflow_stage_rename',
          metadata: { code: @stage.code, name_en: @name_en, name_ur: @name_ur },
          request_id: @request_id,
          occurred_at: Time.current
        )
      end
    end
  end
end
