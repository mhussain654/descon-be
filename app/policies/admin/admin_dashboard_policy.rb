# frozen_string_literal: true

module Admin
  # No natural ActiveRecord subject for a dashboard summary -- authorized
  # against the `:admin_dashboard` symbol passed explicitly with
  # `policy_class:` (same permission-only shape as AuditEventPolicy, which
  # authorizes against the real AuditEvent class since one exists there).
  class AdminDashboardPolicy < ApplicationPolicy
    def show?
      permission_granted?('view_admin_dashboard')
    end
  end
end
