# frozen_string_literal: true

module Api
  module V1
    module Admin
      # The admin Mobilization list: candidates whose flight is recorded, with
      # their departure, ticket, boarding pass and mobilization status.
      class MobilizationsController < ProtectedStaffController
        def index
          authorize ::Candidate, :index?, policy_class: ::Admin::CandidatePolicy

          query = ::Admin::Mobilizations::IndexQuery.new(
            candidate_scope: campaign_selection.apply(policy_scope(::Candidate,
                                                                   policy_scope_class: ::Admin::CandidatePolicy::Scope)),
            params:
          )
          data = query.call.map { |detail| ::Admin::MobilizationSerializer.new(detail).as_json }
          render_collection(data:, pagination: query.pagination,
                            meta: { applied_filters: query.applied_filters, summary: query.summary })
        end
      end
    end
  end
end
