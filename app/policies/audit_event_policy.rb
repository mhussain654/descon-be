# frozen_string_literal: true

class AuditEventPolicy < ApplicationPolicy
  def index?
    permission_granted?('view_audit_events')
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless permission_granted?('view_audit_events')

      scope
    end
  end
end
