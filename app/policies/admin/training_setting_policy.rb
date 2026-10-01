# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the training-link singleton -- a dedicated
  # `manage_training_settings` permission, mirroring
  # AiCallOperationalSettingPolicy's identical shape.
  class TrainingSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_training_settings')
    def update? = permission_granted?('manage_training_settings')
  end
end
