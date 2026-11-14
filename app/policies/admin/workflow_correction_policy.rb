# frozen_string_literal: true

module Admin
  # Authorizes viewing and correcting a candidate's recorded medical
  # appointment, QVC appointment and flight details: developers only (the
  # developer-only `correct_workflow_details` permission).
  class WorkflowCorrectionPolicy < ApplicationPolicy
    def show? = permission_granted?('correct_workflow_details')
    def update? = permission_granted?('correct_workflow_details')
  end
end
