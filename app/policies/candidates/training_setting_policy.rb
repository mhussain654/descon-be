# frozen_string_literal: true

module Candidates
  # Training content isn't per-candidate (it's one shared link every
  # candidate is sent to), so unlike WorkflowPolicy/ProfilePolicy there's no
  # ownership check here -- any authenticated, active candidate may view it.
  class TrainingSettingPolicy < ApplicationPolicy
    def show?
      candidate_authenticated?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end
  end
end
