# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Cross-candidate view over every AI voice call (inbound, admin-
      # triggered, and workflow-stage-triggered), primarily the manual-
      # review queue (see AiCalls::ResolveManualReviewService for the
      # resolution action). Distinct from CandidateAiCallsController, which
      # is scoped to one candidate's admin-triggered call history only.
      class AiCallsController < ProtectedStaffController
        def index
          authorize ::CandidateAiCall, policy_class: ::Admin::CandidateAiCallPolicy

          query = ::Admin::AiCalls::IndexQuery.new(scope: candidate_ai_call_scope, params:)
          calls = query.call

          render_collection(
            data: calls.map { |call_record| serialized(call_record) },
            pagination: query.pagination,
            meta: { applied_filters: query.applied_filters }
          )
        end

        def show
          authorize call_record, policy_class: ::Admin::CandidateAiCallPolicy

          render_success(data: serialized(call_record))
        end

        private

        def candidate_ai_call_scope
          policy_scope(::CandidateAiCall, policy_scope_class: ::Admin::CandidateAiCallPolicy::Scope)
        end

        def call_record
          @call_record ||= candidate_ai_call_scope.find_by!(public_id: params.expect(:id))
        end

        def serialized(call_record)
          ::Admin::CandidateAiCalls::CandidateAiCallSerializer.new(call_record).as_json
        end
      end
    end
  end
end
