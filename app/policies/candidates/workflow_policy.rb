# frozen_string_literal: true

module Candidates
  class WorkflowPolicy < ApplicationPolicy
    def show?
      candidate_authenticated? && owns_candidate?
    end

    def history?
      show?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end

    def owns_candidate?
      record == user
    end
  end
end
