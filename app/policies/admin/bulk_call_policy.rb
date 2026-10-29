# frozen_string_literal: true

module Admin
  # Bulk calls: listing who can be called, starting a batch and reading batch
  # results -- all the same privileged `trigger_ai_calls` action as a single
  # admin-triggered call, just for many candidates at once. Part of the
  # developer-only Communications menu (`access_communications_menu`).
  class BulkCallPolicy < ApplicationPolicy
    def index? = bulk_calls_allowed?
    def show? = bulk_calls_allowed?
    def create? = bulk_calls_allowed?
    def candidates? = bulk_calls_allowed?

    private

    def bulk_calls_allowed?
      permission_granted?('access_communications_menu') && permission_granted?('trigger_ai_calls')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('access_communications_menu') &&
                                 permission_granted?('trigger_ai_calls')

        scope.all
      end
    end
  end
end
