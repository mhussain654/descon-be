# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateQvcAttemptsController < ProtectedStaffController
        include IdempotentRequestHandling

        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_private_state_headers(
            updated_at: candidate.current_assignment&.updated_at,
            etag_key: "#{candidate.public_id}:qvc_attempts"
          )
          render_success(data: qvc_attempts_payload)
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_qvc_attempts.create',
            subject: current_user,
            fingerprint: qvc_attempt_fingerprint,
            required: true
          ) do
            result = ::CandidateWorkflows::QvcAttempts::ScheduleService.call(
              actor: current_user,
              candidate:,
              appointment_date: qvc_attempt_params.fetch(:appointment_date),
              expected_current_stage_code: qvc_attempt_params[:expected_current_stage_code],
              request_id: request.request_id,
              note: qvc_attempt_params[:note]
            )
            set_private_state_headers(
              updated_at: candidate.current_assignment&.reload&.updated_at,
              etag_key: "#{candidate.public_id}:qvc_attempts"
            )
            success_payload(data: serialized_result(result), status: :created)
          end
        end

        def update
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_qvc_attempts.update',
            subject: current_user,
            fingerprint: qvc_attempt_fingerprint,
            required: true
          ) do
            result = ::CandidateWorkflows::QvcAttempts::OutcomeService.call(
              actor: current_user,
              candidate:,
              qvc_attempt_public_id: params.expect(:id),
              outcome_code: qvc_attempt_params[:outcome_code],
              no_show: qvc_attempt_params[:no_show],
              expected_current_stage_code: qvc_attempt_params[:expected_current_stage_code],
              request_id: request.request_id,
              note: qvc_attempt_params[:note]
            )
            set_private_state_headers(
              updated_at: candidate.current_assignment&.reload&.updated_at,
              etag_key: "#{candidate.public_id}:qvc_attempts"
            )
            success_payload(data: serialized_result(result))
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def qvc_attempt_params
          params.expect(candidate_qvc_attempt: %i[appointment_date outcome_code no_show expected_current_stage_code note])
                .to_h
                .deep_symbolize_keys
        end

        def qvc_attempt_fingerprint
          {
            candidate_public_id: candidate.public_id,
            action: action_name,
            qvc_attempt_id: params[:id].presence,
            payload: qvc_attempt_params.deep_stringify_keys
          }.to_json
        end

        def qvc_attempts_payload
          assignment = candidate.current_assignment
          attempts = assignment.blank? ? [] : ::CandidateWorkflows::QvcAttemptQuery.call(scope: assignment.candidate_qvc_attempts)

          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            qvc_attempts: attempts.map { |attempt| ::CandidateWorkflows::AdminQvcAttemptSerializer.new(attempt).as_json },
            updated_at: assignment&.updated_at&.utc&.iso8601
          }
        end

        def serialized_result(result)
          return ::CandidateWorkflows::AdminTransitionResultSerializer.new(result).as_json if result[:history_entry].present?

          ::CandidateWorkflows::AdminQvcAttemptResultSerializer.new(result).as_json
        end
      end
    end
  end
end
