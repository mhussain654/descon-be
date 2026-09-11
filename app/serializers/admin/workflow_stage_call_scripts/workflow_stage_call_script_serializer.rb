# frozen_string_literal: true

module Admin
  module WorkflowStageCallScripts
    class WorkflowStageCallScriptSerializer
      def initialize(script)
        @script = script
      end

      def as_json(*)
        {
          workflow_stage_code: @script.workflow_stage_code,
          announcement: @script.announcement,
          active: @script.active,
          language_code: @script.language_code,
          updated_by: serialized_updated_by,
          updated_at: @script.updated_at.utc.iso8601
        }
      end

      private

      def serialized_updated_by
        actor = @script.updated_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end
