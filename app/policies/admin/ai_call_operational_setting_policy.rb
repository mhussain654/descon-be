# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the AI-call operational rate-limit singleton
  # -- a dedicated `manage_ai_call_settings` permission, independent from
  # `trigger_ai_calls` and `manage_ai_call_scripts` (editing the limits
  # themselves is a distinct, more sensitive grant than either).
  class AiCallOperationalSettingPolicy < ApplicationPolicy
    def show? = permission_granted?('manage_ai_call_settings')
    def update? = permission_granted?('manage_ai_call_settings')
  end
end
