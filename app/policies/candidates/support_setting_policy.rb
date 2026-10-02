# frozen_string_literal: true

module Candidates
  # The support number isn't per-candidate (one shared line), so -- like
  # TrainingSettingPolicy -- any authenticated, active candidate may view it.
  class SupportSettingPolicy < ApplicationPolicy
    def show?
      candidate_authenticated?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end
  end
end
