# frozen_string_literal: true

module Admin
  class CandidateImportPolicy < ApplicationPolicy
    def show?
      permission_granted?('manage_candidates')
    end

    def create?
      permission_granted?('manage_candidates')
    end

    alias preflight? create?
    alias commit? create?
  end
end
