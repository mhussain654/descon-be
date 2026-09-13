# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Read-only, paginated, filterable view over the central Communication
      # log -- every channel (SMS, email, notification, AI voice call) in
      # one place. Index-only, mirrors AuditEventsController: there is no
      # show/create/update/destroy here, since every channel already writes
      # Communication rows through its own provider-specific service.
      class CommunicationsController < ProtectedStaffController
        def index
          authorize ::Communication, policy_class: ::Admin::CommunicationPolicy

          query = ::Admin::Communications::IndexQuery.new(scope: communication_scope, params:)
          communications = query.call

          render_collection(
            data: communications.map { |communication| serialized(communication) },
            pagination: query.pagination,
            meta: { applied_filters: query.applied_filters }
          )
        end

        private

        def communication_scope
          policy_scope(::Communication, policy_scope_class: ::Admin::CommunicationPolicy::Scope)
        end

        def serialized(communication)
          ::Admin::Communications::CommunicationSerializer.new(communication).as_json
        end
      end
    end
  end
end
