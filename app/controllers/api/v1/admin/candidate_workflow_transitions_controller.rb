# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateWorkflowTransitionsController < ProtectedStaffController
        def index
          authorize candidate, :index_transitions?, policy_class: ::Admin::CandidateWorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate:)
          apply_state_headers("#{candidate.public_id}:transitions")
          render_success(data: allowed_transitions_payload(snapshot))
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_workflow_transitions.create',
            subject: current_user,
            fingerprint: transition_fingerprint,
            required: true
          ) do
            render_transition_payload
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def transition_params
          params.expect(candidate_workflow_transition: [
                          :to_stage_code,
                          :expected_current_stage_code,
                          :reason_code,
                          :note,
                          { evidence: {} }
                        ]).to_h.deep_symbolize_keys
        end

        def transition_fingerprint
          ::CandidateWorkflows::TransitionFingerprint.call(
            candidate_public_id: candidate.public_id,
            transition: transition_params
          )
        end

        def allowed_transitions_payload(snapshot)
          {
            candidate_id: candidate.public_id,
            updated_at: snapshot.updated_at,
            allowed_next_transitions: ::CandidateWorkflows::AllowedTransitionsService.call(
              actor: current_user,
              candidate:
            )
          }
        end

        def render_transition_payload
          result = ::CandidateWorkflows::TransitionService.call(
            actor: current_user,
            candidate:,
            request_id: request.request_id,
            **transition_params
          )
          apply_state_headers("#{candidate.public_id}:transition")
          success_payload(data: serialized_transition_result(result), status: :created)
        end

        def serialized_transition_result(result)
          ::CandidateWorkflows::TransitionResultSerializer.new(result).as_json
        end

        def apply_state_headers(etag_key)
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key:
          )
        end
      end
    end
  end
end
