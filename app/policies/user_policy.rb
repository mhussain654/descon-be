# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    permission_granted?('manage_staff_users')
  end

  def show?
    staff_authenticated? && self_record?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless permission_granted?('manage_staff_users')

      scope
    end
  end
end
