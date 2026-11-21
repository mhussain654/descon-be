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

    def access?
      show?
    end

    # A boarding pass photo is reviewed like a document, so document reviewers
    # (HR) may reject one as well as staff who manage the workflow.
    def reject_boarding_pass?
      permission_granted?('manage_candidate_documents') || permission_granted?('manage_workflow')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_workflow') || permission_granted?('manage_workflow')

        scope.all
      end
    end
  end
end
