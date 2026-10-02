# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the support-number singleton -- a dedicated
  # `manage_support_settings` permission, mirroring TrainingSettingPolicy.
  class SupportSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_support_settings')
    def update? = permission_granted?('manage_support_settings')
  end
end
