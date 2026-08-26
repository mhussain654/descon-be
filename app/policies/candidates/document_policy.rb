# frozen_string_literal: true

module Candidates
  class DocumentPolicy < ApplicationPolicy
    def index?
      candidate_authenticated? && owns_record?
    end

    def create?
      index?
    end

    private

    def candidate_authenticated?
      user.present? && user.respond_to?(:active_for_authentication?) && user.active_for_authentication?
    end

    def owns_record?
      record == user
    end
  end
end
