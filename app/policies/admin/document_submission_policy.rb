# frozen_string_literal: true

module Admin
  class DocumentSubmissionPolicy < ApplicationPolicy
    def index?
      permission_granted?('manage_candidate_documents')
    end

    def show?
      index?
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('manage_candidate_documents')

        scope.all
      end
    end
  end
end
