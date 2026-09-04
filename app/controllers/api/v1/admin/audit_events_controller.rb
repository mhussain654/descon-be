# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Read-only audit-event browsing (MPS-807). Deliberately index-only --
      # no show/update/destroy: audit records must never be editable through
      # application APIs, and there is no separate detail fetch to guard
      # against an insecure direct object reference on `id`.
      class AuditEventsController < ProtectedStaffController
        def index
          authorize ::AuditEvent

          query = ::Admin::AuditEvents::IndexQuery.new(scope: audit_event_scope, params:)
          events = query.call

          render_collection(
            data: events.map { |event| ::Admin::AuditEventSerializer.new(event).as_json },
            pagination: query.pagination,
            meta: { applied_filters: query.applied_filters }
          )
        end

        private

        def audit_event_scope
          policy_scope(::AuditEvent)
        end
      end
    end
  end
end
