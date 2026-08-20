# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def show?
    user.present? && record == user
  end
end
