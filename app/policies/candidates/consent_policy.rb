# frozen_string_literal: true

module Candidates
  class ConsentPolicy < ApplicationPolicy
    def show?
      candidate_authenticated?
    end

    def create?
      candidate_authenticated?
    end

    private

    def candidate_authenticated?
      user.present? && user.active_for_authentication?
    end
  end
end
