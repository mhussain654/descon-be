# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing per-workflow-stage AI call scripts -- a
  # dedicated `manage_ai_call_scripts` permission, independent from
  # `trigger_ai_calls` (editing what an automated call says is a distinct,
  # independently-auditable grant from triggering a call by hand).
  class WorkflowStageCallScriptPolicy < ApplicationPolicy
    def index? = permission_granted?('manage_ai_call_scripts')
    def update? = permission_granted?('manage_ai_call_scripts')

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('manage_ai_call_scripts')

        scope.all
      end
    end
  end
end
