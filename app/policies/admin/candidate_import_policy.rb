# frozen_string_literal: true

module Admin
  class CandidateImportPolicy < ApplicationPolicy
    def create?
      permission_granted?('manage_candidates')
    end
  end
end
