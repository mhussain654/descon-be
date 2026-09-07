# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff record and list a candidate's visa application outcomes, advancing their workflow.
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

        # Returns the candidate's current assignment and its list of visa decisions.
        def index
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: visa_decisions_payload)
        end

        # Records a new visa decision for the candidate (with visa copy upload), idempotently,
        # advancing the workflow.
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

        # Refreshes caching headers and builds the serialized success response body.
        def success_response(result:, status:)
          set_state_headers
          success_payload(data: ::CandidateWorkflows::AdminVisaDecisionResultSerializer.new(result).as_json, status:)
        end

        # Loads the candidate for this action within the staff member's authorized scope,
        # raising if not found.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Allowlists the visa decision fields from the request body.
        def visa_decision_params
          params.expect(candidate_visa_decision: VISA_DECISION_PARAMS)
        end

        # Builds the payload used for the idempotency fingerprint, excluding the uploaded file itself.
        def fingerprint_payload
          visa_decision_params.except(:visa_copy).to_h.deep_symbolize_keys
        end

        # Computes an idempotency fingerprint that accounts for the uploaded visa copy file.
        def create_fingerprint
          ::CandidateWorkflows::VisaDecisions::UploadFingerprint.call(
            request:,
            candidate_public_id: candidate.public_id,
            payload: fingerprint_payload,
            uploaded_file: visa_decision_params[:visa_copy]
          )
        end

        # Assembles the arguments for the visa decision recording service.
        def record_payload
          {
            actor: current_user,
            candidate: candidate,
            request_id: request.request_id
          }.merge(decision_fields)
        end

        # Extracts the decision-specific fields (outcome, date, rejection reason, visa copy, etc.).
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

        # Builds the index response body: candidate/assignment ids plus the serialized decision list.
        def visa_decisions_payload
          assignment = candidate.current_assignment
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            visa_decisions: serialized_visa_decisions(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        # Serializes the assignment's visa decisions, or an empty list if there is no assignment.
        def serialized_visa_decisions(assignment)
          return [] if assignment.blank?

          queried_decisions(assignment).map do |decision|
            ::CandidateWorkflows::AdminVisaDecisionSerializer.new(decision).as_json
          end
        end

        # Queries the assignment's visa decisions via the shared query object.
        def queried_decisions(assignment)
          ::CandidateWorkflows::VisaDecisionQuery.call(scope: assignment.candidate_visa_decisions)
        end

        # Formats the assignment's updated-at timestamp as UTC ISO8601, or nil if absent.
        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        # Sets caching/concurrency headers (Last-Modified/ETag) from the candidate's current assignment.
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
