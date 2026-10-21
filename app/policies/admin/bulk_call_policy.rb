# frozen_string_literal: true

module Admin
  # Bulk calls: listing who can be called, starting a batch and reading batch
  # results -- all the same privileged `trigger_ai_calls` action as a single
  # admin-triggered call, just for many candidates at once.
  class BulkCallPolicy < ApplicationPolicy
    def index? = permission_granted?('trigger_ai_calls')
    def show? = permission_granted?('trigger_ai_calls')
    def create? = permission_granted?('trigger_ai_calls')
    def candidates? = permission_granted?('trigger_ai_calls')

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('trigger_ai_calls')

        scope.all
      end
    end
  end
end
