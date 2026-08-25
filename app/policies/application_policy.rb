# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  private

  def staff_authenticated?
    user.present? && user.authorization_active?
  end

  def permission_granted?(permission_code)
    staff_authenticated? && user.permission?(permission_code)
  end

  def self_record?
    user.present? && record == user
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

    def staff_authenticated?
      user.present? && user.authorization_active?
    end

    def permission_granted?(permission_code)
      staff_authenticated? && user.permission?(permission_code)
    end
  end
end
