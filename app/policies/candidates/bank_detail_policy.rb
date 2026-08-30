# frozen_string_literal: true

module Candidates
  class BankDetailPolicy < ApplicationPolicy
    def show?
      candidate_authenticated?
    end

    def update?
      candidate_authenticated?
    end

    private

    def candidate_authenticated?
      user.present? && user.active_for_authentication?
    end
  end
end
