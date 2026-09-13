# frozen_string_literal: true

module Admin
  # Authorizes admin-triggered AI voice calls -- a dedicated `trigger_ai_calls`
  # permission, independently grantable from generic candidate-management
  # permissions (mirrors Admin::PaymentPolicy's index/show shape, but
  # `create` is gated by the same single permission since triggering and
  # viewing an admin-triggered call are the same privileged action here).
  class CandidateAiCallPolicy < ApplicationPolicy
    def index? = permission_granted?('trigger_ai_calls')
    def create? = permission_granted?('trigger_ai_calls')

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('trigger_ai_calls')

        scope.all
      end
    end
  end
end
