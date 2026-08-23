# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def show?
    user.present? && record == user
  end

  class Scope < Scope
    def resolve
      return scope.none unless user&.admin?

      scope
    end
  end
end
