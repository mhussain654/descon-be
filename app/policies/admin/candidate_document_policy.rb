# frozen_string_literal: true

module Admin
  class CandidateDocumentPolicy < ApplicationPolicy
    def access?
      permission_granted?('manage_candidate_documents')
    end

    def verify?
      access?
    end

    def reject?
      access?
    end

    def extraction?
      access?
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('manage_candidate_documents')

        scope.current_version.joins(:submission_item).distinct
      end
    end
  end
end
