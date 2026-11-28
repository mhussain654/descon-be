# frozen_string_literal: true

module Admin
  # Any signed-in staff member may choose which sender a candidate's SMS go
  # out from (client decision); which candidates they can reach is still
  # limited by Admin::CandidateWorkflowPolicy::Scope.
  class CandidateSmsSenderPolicy < ApplicationPolicy
    def update? = staff_authenticated?
  end
end
