# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff trigger and review admin-triggered outbound AI voice
      # calls for one candidate (one of the 4 scenarios in
      # AiCalls::Prompts::ScenarioPromptRegistry). Deliberately index+create
      # only -- a call's outcome is written only by the post-call webhook/
      # reconciliation job, never through this API.
      class CandidateAiCallsController < ProtectedStaffController
        include IdempotentRequestHandling

        CALL_REASONS = ::AiCalls::Prompts::ScenarioPromptRegistry::PROMPTS_BY_CALL_REASON.keys.freeze

        # Returns this candidate's admin-triggered call history, most recent first.
        def index
          authorize ::CandidateAiCall, policy_class: ::Admin::CandidateAiCallPolicy

          render_success(data: candidate_calls.map { |call| serialized(call) })
        end

        # Triggers a new outbound AI voice call for this candidate, idempotently.
        def create
          authorize ::CandidateAiCall, policy_class: ::Admin::CandidateAiCallPolicy

          render_idempotent_response(scope: 'admin.candidate_ai_calls.create', subject: current_user, required: true) do
            call_record = ::AiCalls::TriggerOutboundCallService.call(
              candidate:, plan: ::AiCalls::OutboundCallPlan.for_admin_scenario(call_reason_param),
              actor: current_user, request_id: request.request_id
            )
            success_payload(data: serialized(call_record), status: :created)
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def candidate_calls
          policy_scope(::CandidateAiCall, policy_scope_class: ::Admin::CandidateAiCallPolicy::Scope)
            .outbound.where(candidate:).order(created_at: :desc)
        end

        def call_reason_param
          value = params.expect(candidate_ai_call: [:call_reason]).fetch(:call_reason).to_s
          raise ValidationError.new(field: 'candidate_ai_call.call_reason') unless CALL_REASONS.include?(value)

          value
        end

        def serialized(call_record)
          ::Admin::CandidateAiCalls::CandidateAiCallSerializer.new(call_record).as_json
        end
      end
    end
  end
end
