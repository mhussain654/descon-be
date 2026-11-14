# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the default QVC appointment: staff who move
  # candidates through the workflow (`manage_workflow` -- Admin and MPS).
  class QvcAppointmentSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_workflow')
    def update? = permission_granted?('manage_workflow')
  end
end
