# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff list and record a candidate's medical results (fit/unfit). The first result
      # moves the candidate into their process's medical-outcome stage; later ones re-decide an
      # unfit result while the candidate is held there.
      class CandidateMedicalResultsController < ProtectedStaffController
        include IdempotentRequestHandling

        MEDICAL_RESULT_PARAMS = %i[outcome_code result_date note expected_current_stage_code].freeze

        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: index_payload)
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_medical_results.create',
            subject: current_user,
            fingerprint: { candidate_id: candidate.public_id, **medical_result_params.to_h }.to_json,
            required: true
          ) { record_result }
        end

        private

        def record_result
          result = ::CandidateWorkflows::MedicalResults::RecordService.call(**record_payload)
          set_state_headers
          success_payload(data: result_payload(result), status: :created)
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def medical_result_params
          params.expect(candidate_medical_result: MEDICAL_RESULT_PARAMS)
        end

        def record_payload
          {
            actor: current_user, candidate:, request_id: request.request_id,
            **medical_result_params.to_h.symbolize_keys
          }
        end

        def result_payload(result)
          {
            workflow: ::CandidateWorkflows::StateSerializer.new(result.fetch(:snapshot)).as_json,
            medical_result: ::CandidateWorkflows::AdminMedicalResultSerializer.new(result.fetch(:medical_result)).as_json
          }
        end

        def index_payload
          assignment = candidate.current_assignment
          results = assignment ? assignment.candidate_medical_results.includes(:recorded_by).latest_first : []
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            medical_results: results.map do |result|
              ::CandidateWorkflows::AdminMedicalResultSerializer.new(result).as_json
            end,
            updated_at: assignment && assignment.updated_at.utc.iso8601
          }
        end

        def set_state_headers
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key: "#{candidate.public_id}:medical_results"
          )
        end
      end
    end
  end
end
