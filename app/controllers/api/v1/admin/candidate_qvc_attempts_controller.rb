# frozen_string_literal: true

module Api
  module V1
    module Admin
      # rubocop:disable Metrics/ClassLength
      # Lets staff schedule and record outcomes for a candidate's qualifying visa
      # counselling (QVC) appointments, and lists that history.
      class CandidateQvcAttemptsController < ProtectedStaffController
        include IdempotentRequestHandling

        QVC_ATTEMPT_PARAMS = %i[
          appointment_date
          outcome_code
          no_show
          expected_current_stage_code
          note
        ].freeze

        # Returns the candidate's current assignment and its list of QVC attempts.
        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: qvc_attempts_payload)
        end

        # Schedules a new QVC appointment for the candidate, idempotently, advancing the workflow.
        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          with_idempotent_response(scope: 'admin.candidate_qvc_attempts.create') do
            result = ::CandidateWorkflows::QvcAttempts::ScheduleService.call(**schedule_payload)
            success_response(result:, status: :created)
          end
        end

        # Records the outcome of an existing QVC appointment, idempotently, advancing the workflow.
        def update
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          with_idempotent_response(scope: 'admin.candidate_qvc_attempts.update') do
            result = ::CandidateWorkflows::QvcAttempts::OutcomeService.call(**outcome_payload)
            success_response(result:)
          end
        end

        private

        # Loads the candidate for this action within the staff member's authorized scope,
        # raising if not found.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Allowlists and symbolizes the QVC attempt fields from the request body.
        def qvc_attempt_params
          params.expect(candidate_qvc_attempt: QVC_ATTEMPT_PARAMS)
                .to_h
                .deep_symbolize_keys
        end

        # Builds the idempotency fingerprint from the candidate, action, target attempt id and payload.
        def qvc_attempt_fingerprint
          {
            candidate_public_id: candidate.public_id,
            action: action_name,
            qvc_attempt_id: params[:id].presence,
            payload: qvc_attempt_params.deep_stringify_keys
          }.to_json
        end

        # Builds the index response body: candidate/assignment ids plus the serialized attempt list.
        def qvc_attempts_payload
          assignment = candidate.current_assignment
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            qvc_attempts: serialized_qvc_attempts(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        # Serializes a create/update result, using the workflow-transition shape when the
        # outcome also advanced the candidate's stage, otherwise the plain QVC-attempt shape.
        def serialized_result(result)
          if result[:history_entry].present?
            return ::CandidateWorkflows::AdminTransitionResultSerializer.new(result).as_json
          end

          ::CandidateWorkflows::AdminQvcAttemptResultSerializer.new(result).as_json
        end

        # Shares idempotent-response handling between create and update, keyed by the given scope.
        def with_idempotent_response(scope:, &)
          render_idempotent_response(
            scope:,
            subject: current_user,
            fingerprint: qvc_attempt_fingerprint,
            required: true,
            &
          )
        end

        # Assembles the arguments for the QVC appointment scheduling service.
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

        # Assembles the arguments for the QVC appointment outcome-recording service.
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

        # Refreshes caching headers and builds the success response body for create/update.
        def success_response(result:, status: :ok)
          set_state_headers
          success_payload(data: serialized_result(result), status:)
        end

        # Sets caching/concurrency headers (Last-Modified/ETag) from the candidate's current assignment.
        def set_state_headers
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key: "#{candidate.public_id}:qvc_attempts"
          )
        end

        # Serializes the assignment's QVC attempts, or an empty list if there is no assignment.
        def serialized_qvc_attempts(assignment)
          return [] if assignment.blank?

          queried_attempts(assignment).map { |attempt| serialize_attempt(attempt) }
        end

        # Formats the assignment's updated-at timestamp as UTC ISO8601, or nil if absent.
        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        # Queries the assignment's QVC attempts via the shared query object.
        def queried_attempts(assignment)
          ::CandidateWorkflows::QvcAttemptQuery.call(scope: assignment.candidate_qvc_attempts)
        end

        # Serializes a single QVC attempt for the admin API response shape.
        def serialize_attempt(attempt)
          ::CandidateWorkflows::AdminQvcAttemptSerializer.new(attempt).as_json
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
