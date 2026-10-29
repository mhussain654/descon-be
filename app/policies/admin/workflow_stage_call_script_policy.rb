# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing per-workflow-stage AI call scripts -- a
  # dedicated `manage_ai_call_scripts` permission, independent from
  # `trigger_ai_calls` (editing what an automated call says is a distinct,
  # independently-auditable grant from triggering a call by hand). Part of the
  # developer-only Communications menu (`access_communications_menu`).
  class WorkflowStageCallScriptPolicy < ApplicationPolicy
    def index? = scripts_allowed?
    def update? = scripts_allowed?

    private

    def scripts_allowed?
      permission_granted?('access_communications_menu') && permission_granted?('manage_ai_call_scripts')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('access_communications_menu') &&
                                 permission_granted?('manage_ai_call_scripts')

        scope.all
      end
    end
  end
end
