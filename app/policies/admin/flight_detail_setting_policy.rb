# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the default flight details: staff who move
  # candidates through the workflow (`manage_workflow` -- Admin and MPS).
  class FlightDetailSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_workflow')
    def update? = permission_granted?('manage_workflow')
  end
end
