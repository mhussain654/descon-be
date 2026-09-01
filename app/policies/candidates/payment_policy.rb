# frozen_string_literal: true

module Candidates
  class PaymentPolicy < ApplicationPolicy
    def show?
      candidate_authenticated? && owns_candidate?
    end

    def create?
      show?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end

    def owns_candidate?
      user == record
    end
  end
end
