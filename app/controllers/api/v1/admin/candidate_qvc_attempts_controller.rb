# frozen_string_literal: true

module Api
  module V1
    module Admin
      # rubocop:disable Metrics/ClassLength
      class CandidateQvcAttemptsController < ProtectedStaffController
        include IdempotentRequestHandling

        QVC_ATTEMPT_PARAMS = %i[
          appointment_date
          outcome_code
          no_show
          expected_current_stage_code
          note
        ].freeze

        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: qvc_attempts_payload)
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          with_idempotent_response(scope: 'admin.candidate_qvc_attempts.create') do
            result = ::CandidateWorkflows::QvcAttempts::ScheduleService.call(**schedule_payload)
            success_response(result:, status: :created)
          end
        end

        def update
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          with_idempotent_response(scope: 'admin.candidate_qvc_attempts.update') do
            result = ::CandidateWorkflows::QvcAttempts::OutcomeService.call(**outcome_payload)
            success_response(result:)
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def qvc_attempt_params
          params.expect(candidate_qvc_attempt: QVC_ATTEMPT_PARAMS)
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
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            qvc_attempts: serialized_qvc_attempts(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        def serialized_result(result)
          if result[:history_entry].present?
            return ::CandidateWorkflows::AdminTransitionResultSerializer.new(result).as_json
          end

          ::CandidateWorkflows::AdminQvcAttemptResultSerializer.new(result).as_json
        end

        def with_idempotent_response(scope:, &)
          render_idempotent_response(
            scope:,
            subject: current_user,
            fingerprint: qvc_attempt_fingerprint,
            required: true,
            &
          )
        end

        def schedule_payload
          {
            actor: current_user,
            candidate: candidate,
            appointment_date: qvc_attempt_params.fetch(:appointment_date),
            expected_current_stage_code: qvc_attempt_params[:expected_current_stage_code],
            request_id: request.request_id,
            note: qvc_attempt_params[:note]
          }
        end

        def outcome_payload
          {
            actor: current_user,
            candidate: candidate,
            qvc_attempt_public_id: params.expect(:id),
            outcome_code: qvc_attempt_params[:outcome_code],
            no_show: qvc_attempt_params[:no_show],
            expected_current_stage_code: qvc_attempt_params[:expected_current_stage_code],
            request_id: request.request_id,
            note: qvc_attempt_params[:note]
          }
        end

        def success_response(result:, status: :ok)
          set_state_headers
          success_payload(data: serialized_result(result), status:)
        end

        def set_state_headers
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key: "#{candidate.public_id}:qvc_attempts"
          )
        end

        def serialized_qvc_attempts(assignment)
          return [] if assignment.blank?

          queried_attempts(assignment).map { |attempt| serialize_attempt(attempt) }
        end

        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        def queried_attempts(assignment)
          ::CandidateWorkflows::QvcAttemptQuery.call(scope: assignment.candidate_qvc_attempts)
        end

        def serialize_attempt(attempt)
          ::CandidateWorkflows::AdminQvcAttemptSerializer.new(attempt).as_json
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
