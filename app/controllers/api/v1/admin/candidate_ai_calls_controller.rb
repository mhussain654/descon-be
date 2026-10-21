# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff place one call to a candidate with a named call type (an
      # active RobocallVoice) and review every call the candidate has had --
      # manual, automatic (workflow stage) and bulk. Deliberately index+create
      # only -- a call's outcome is written only by the post-call webhook/
      # reconciliation job, never through this API.
      class CandidateAiCallsController < ProtectedStaffController
        include IdempotentRequestHandling

        HISTORY_LIMIT = 50

        # Returns this candidate's outbound call history, most recent first.
        def index
          authorize ::CandidateAiCall, policy_class: ::Admin::CandidateAiCallPolicy

          calls = candidate_calls.to_a
          voices = RobocallVoice.where(voice_id: calls.filter_map(&:provider_voice_id).uniq).index_by(&:voice_id)
          render_success(data: calls.map { |call| serialized(call, voices) })
        end

        # Places a call to this candidate with the chosen call type, idempotently.
        def create
          authorize ::CandidateAiCall, policy_class: ::Admin::CandidateAiCallPolicy

          render_idempotent_response(scope: 'admin.candidate_ai_calls.create', subject: current_user, required: true) do
            voice = robocall_voice
            call_record = ::AiCalls::TriggerOutboundCallService.call(
              candidate:, plan: ::AiCalls::OutboundCallPlan.for_voice(voice_id: voice.voice_id),
              actor: current_user, request_id: request.request_id
            )
            success_payload(data: serialized(call_record, { voice.voice_id => voice }), status: :created)
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def candidate_calls
          policy_scope(::CandidateAiCall, policy_scope_class: ::Admin::CandidateAiCallPolicy::Scope)
            .outbound.where(candidate:).includes(:candidate, :triggered_by, :reviewed_by)
            .order(created_at: :desc).limit(HISTORY_LIMIT)
        end

        # Only an active call type can be called with; the library is managed on
        # the Bulk calls page.
        def robocall_voice
          id = params.expect(candidate_ai_call: [:robocall_voice_id]).fetch(:robocall_voice_id).to_s
          ::RobocallVoice.active.find_by(public_id: id) ||
            raise(ValidationError.new(field: 'candidate_ai_call.robocall_voice_id'))
        end

        def serialized(call_record, voices)
          ::Admin::CandidateAiCalls::CandidateAiCallSerializer.new(call_record, voices:).as_json
        end
      end
    end
  end
end
