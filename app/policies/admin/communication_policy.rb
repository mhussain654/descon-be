# frozen_string_literal: true

module Admin
  # Authorizes read access to the central Communication log (SMS/email/
  # notification/AI-voice-call records) -- part of the developer-only
  # Communications menu (`access_communications_menu`), and then granted by
  # either the read-only `view_communications` permission or
  # `manage_communications` (a role that can send/manage communications can
  # also see what was sent). Mirrors Admin::PaymentPolicy's view-or-manage shape.
  class CommunicationPolicy < ApplicationPolicy
    def index? = communications_visible?

    private

    def communications_visible?
      permission_granted?('access_communications_menu') &&
        (permission_granted?('view_communications') || permission_granted?('manage_communications'))
    end

    class Scope < Scope
      def resolve
        return scope.none unless communications_visible?

        scope.all
      end

      private

      def communications_visible?
        permission_granted?('access_communications_menu') &&
          (permission_granted?('view_communications') || permission_granted?('manage_communications'))
      end
    end
  end
end
