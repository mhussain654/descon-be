# frozen_string_literal: true

# Backups are infra-sensitive -- only the admin role (via manage_backups) may browse or
# download them, unlike most other admin resources where mps/management also get read access.
class SystemDatabaseBackupPolicy < ApplicationPolicy
  def index?
    permission_granted?('manage_backups')
  end

  def access?
    permission_granted?('manage_backups')
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless permission_granted?('manage_backups')

      scope
    end
  end
end
