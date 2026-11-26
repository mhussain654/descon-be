# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    permission_granted?('manage_staff_users')
  end

  def create?
    permission_granted?('manage_staff_users')
  end

  def update?
    permission_granted?('manage_staff_users')
  end

  def show?
    staff_authenticated? && self_record?
  end

  # A staff member's own profile settings (the working campaign).
  def update_profile? = show?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless permission_granted?('manage_staff_users')

      # Only accounts at or below the staff member's own level (User#visible_staff_role_codes).
      scope.where(role: user.visible_staff_role_codes)
    end
  end
end
