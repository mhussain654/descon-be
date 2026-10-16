# frozen_string_literal: true

module Candidates
  class TrainingVideoPolicy < ApplicationPolicy
    def index? = user.present? && user.active_for_authentication?
  end
end
