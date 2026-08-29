# frozen_string_literal: true

module Admin
  class CandidateWorkflowPolicy < ApplicationPolicy
    def show?
      permission_granted?('view_workflow') || permission_granted?('manage_workflow')
    end

    def history?
      show?
    end

    def index_transitions?
      show?
    end

    def create_transition?
      permission_granted?('manage_workflow')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_workflow') || permission_granted?('manage_workflow')

        scope.all
      end
    end
  end
end
