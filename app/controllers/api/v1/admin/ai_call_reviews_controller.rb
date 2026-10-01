# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Resolves a needs_manual_review CandidateAiCall -- see
      # AiCalls::ResolveManualReviewService. Create-only: a resolution, once
      # made, stands (AiCallNotAwaitingReviewError blocks a second attempt).
      class AiCallReviewsController < ProtectedStaffController
        OUTCOMES = ::CandidateAiCall::OUTCOMES

        def create
          authorize call_record, :review?, policy_class: ::Admin::CandidateAiCallPolicy

          result = ::AiCalls::ResolveManualReviewService.call(
            candidate_ai_call: call_record, actor: current_user, outcome: outcome_param,
            outcome_reason: review_params[:outcome_reason], notes: review_params[:notes],
            request_id: request.request_id
          )

          render_success(data: serialized(result), status: :created)
        end

        private

        def call_record
          @call_record ||= policy_scope(::CandidateAiCall, policy_scope_class: ::Admin::CandidateAiCallPolicy::Scope)
                           .find_by!(public_id: params.expect(:ai_call_id))
        end

        def review_params
          params.permit(:outcome, :outcome_reason, :notes)
        end

        def outcome_param
          value = review_params.fetch(:outcome, '').to_s
          raise ValidationError.new(field: 'outcome') unless OUTCOMES.include?(value)

          value
        end

        def serialized(call_record)
          ::Admin::CandidateAiCalls::CandidateAiCallSerializer.new(call_record).as_json
        end
      end
    end
  end
end
