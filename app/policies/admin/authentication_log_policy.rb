# frozen_string_literal: true

module Admin
  # Authorizes reading who signed in and when (staff logins, candidate OTPs
  # and app use): developers only (the developer-only
  # `view_authentication_logs` permission).
  class AuthenticationLogPolicy < ApplicationPolicy
    def index? = permission_granted?('view_authentication_logs')

    def show? = index?

    # Every row for developers; nothing for anyone else.
    class Scope < ApplicationPolicy::Scope
      def resolve
        return scope.none unless permission_granted?('view_authentication_logs')

        scope
      end
    end
  end
end
