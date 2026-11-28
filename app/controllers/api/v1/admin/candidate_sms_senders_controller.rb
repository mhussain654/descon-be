# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Changes which sender a candidate's SMS go out from: the "DESCON MPS"
      # brand name or the short code. Setting a value is idempotent by nature.
      class CandidateSmsSendersController < ProtectedStaffController
        def update
          authorize candidate, policy_class: ::Admin::CandidateSmsSenderPolicy

          ::CandidateSms::UpdateSender.call(candidate:, sms_sender: sender_param, actor: current_user,
                                            request_id: request.request_id)
          render_success(data: { sender: candidate.sms_sender })
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def sender_param = params.expect(sms_sender: [:sender])[:sender]
      end
    end
  end
end
