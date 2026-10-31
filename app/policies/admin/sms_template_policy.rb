# frozen_string_literal: true

module Admin
  # Authorizes viewing/editing the send.pk message templates -- part of App
  # Settings, so the same developer-only `manage_app_settings` permission.
  class SmsTemplatePolicy < ApplicationPolicy
    def index? = permission_granted?('manage_app_settings')
    def update? = permission_granted?('manage_app_settings')

    class Scope < Scope
      def resolve
        permission_granted?('manage_app_settings') ? scope.all : scope.none
      end
    end
  end
end
