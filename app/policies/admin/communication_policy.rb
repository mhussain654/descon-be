# frozen_string_literal: true

module Admin
  # Authorizes read access to the central Communication log (SMS/email/
  # notification/AI-voice-call records). A read-only report, so every active
  # staff member may see it; sending and the call tools stay behind their own
  # permissions.
  class CommunicationPolicy < ApplicationPolicy
    def index? = staff_authenticated?

    class Scope < Scope
      def resolve
        return scope.none unless staff_authenticated?

        scope.all
      end
    end
  end
end
