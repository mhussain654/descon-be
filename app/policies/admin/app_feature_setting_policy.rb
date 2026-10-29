# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the App Settings feature switches -- the
  # dedicated, admin-only `manage_app_settings` permission.
  class AppFeatureSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_app_settings')
    def update? = permission_granted?('manage_app_settings')
  end
end
