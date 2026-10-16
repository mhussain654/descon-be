# frozen_string_literal: true

module Admin
  class TrainingVideoPolicy < ApplicationPolicy
    def index? = permission_granted?('manage_training_settings')
    def create? = index?
    def update? = index?
    def destroy? = index?
  end
end
