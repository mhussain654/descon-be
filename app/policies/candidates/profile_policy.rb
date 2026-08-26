# frozen_string_literal: true

module Candidates
  class ProfilePolicy < ApplicationPolicy
    def show?
      candidate_authenticated? && owns_profile?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end

    def owns_profile?
      record == user
    end
  end
end
