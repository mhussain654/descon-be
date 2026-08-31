# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateVisaDecisionsController < ProtectedStaffController
        include IdempotentRequestHandling

        VISA_DECISION_PARAMS = %i[
          outcome_code
          decision_date
          rejection_reason_code
          visa_copy
          expected_current_stage_code
          note
        ].freeze

        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: visa_decisions_payload)
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_visa_decisions.create',
            subject: current_user,
            fingerprint: create_fingerprint,
            required: true
          ) do
            result = ::CandidateWorkflows::VisaDecisions::RecordService.call(**record_payload)
            success_response(result:, status: :created)
          end
        end

        private

        def success_response(result:, status:)
          set_state_headers
          success_payload(data: ::CandidateWorkflows::AdminVisaDecisionResultSerializer.new(result).as_json, status:)
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def visa_decision_params
          params.expect(candidate_visa_decision: VISA_DECISION_PARAMS)
        end

        def fingerprint_payload
          visa_decision_params.except(:visa_copy).to_h.deep_symbolize_keys
        end

        def create_fingerprint
          ::CandidateWorkflows::VisaDecisions::UploadFingerprint.call(
            request:,
            candidate_public_id: candidate.public_id,
            payload: fingerprint_payload,
            uploaded_file: visa_decision_params[:visa_copy]
          )
        end

        def record_payload
          {
            actor: current_user,
            candidate: candidate,
            request_id: request.request_id
          }.merge(decision_fields)
        end

        def decision_fields
          {
            outcome_code: visa_decision_params[:outcome_code],
            decision_date: visa_decision_params[:decision_date],
            rejection_reason_code: visa_decision_params[:rejection_reason_code],
            visa_copy: visa_decision_params[:visa_copy],
            expected_current_stage_code: visa_decision_params[:expected_current_stage_code],
            note: visa_decision_params[:note]
          }
        end

        def visa_decisions_payload
          assignment = candidate.current_assignment
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            visa_decisions: serialized_visa_decisions(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        def serialized_visa_decisions(assignment)
          return [] if assignment.blank?

          queried_decisions(assignment).map do |decision|
            ::CandidateWorkflows::AdminVisaDecisionSerializer.new(decision).as_json
          end
        end

        def queried_decisions(assignment)
          ::CandidateWorkflows::VisaDecisionQuery.call(scope: assignment.candidate_visa_decisions)
        end

        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        def set_state_headers
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key: "#{candidate.public_id}:visa_decisions"
          )
        end
      end
    end
  end
end
