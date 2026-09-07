# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Exposes a candidate's allowed next workflow-stage transitions and
      # lets staff move a candidate forward/backward through the 15-stage
      # recruitment pipeline, with idempotency and optimistic-concurrency
      # guards around each transition.
      # rubocop:disable Metrics/ClassLength
      class CandidateWorkflowTransitionsController < ProtectedStaffController
        # Returns the candidate's current workflow snapshot plus the list of
        # transitions the current staff member is allowed to make next.
        def index
          authorize candidate, :index_transitions?, policy_class: ::Admin::CandidateWorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate:)
          apply_state_headers("#{candidate.public_id}:transitions")
          render_success(data: allowed_transitions_payload(snapshot))
        end

        # Applies a workflow-stage transition for the candidate and returns
        # the resulting state; deduplicated via the idempotency fingerprint
        # so a retried request does not apply the transition twice.
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

        # Loads the candidate named in the route, scoped to what the current
        # staff member is authorized to view/manage.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Validates and permits the incoming transition params, including the
        # target-stage-specific evidence fields, returning a symbolized hash.
        def transition_params
          raw_transition = raw_transition_params
          validate_expected_current_stage_requirement!(raw_transition)
          validate_evidence_keys!(raw_transition[:to_stage_code], raw_transition[:evidence])
          permitted_transition_params(raw_transition[:to_stage_code]).to_h.deep_symbolize_keys
        end

        # Builds the idempotency-key fingerprint for this transition request,
        # based on the candidate and the requested transition payload.
        def transition_fingerprint
          ::CandidateWorkflows::TransitionFingerprint.call(
            candidate_public_id: candidate.public_id,
            transition: transition_params
          )
        end

        # Assembles the index response body: candidate id, snapshot
        # timestamp, and the set of transitions currently allowed.
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

        # Executes the transition via TransitionService and serializes the
        # created result for the response.
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

        # Serializes a transition result for the API response.
        def serialized_transition_result(result)
          ::CandidateWorkflows::AdminTransitionResultSerializer.new(result).as_json
        end

        # Sets the private cache/ETag headers for this candidate's workflow
        # state, keyed off the candidate's current assignment timestamp.
        def apply_state_headers(etag_key)
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key:
          )
        end

        # Reads the raw (not yet stage-specific) transition params from the
        # request body, before evidence fields are narrowed by target stage.
        def raw_transition_params
          params.expect(candidate_workflow_transition: [
                          :to_stage_code,
                          :expected_current_stage_code,
                          :reason_code,
                          :note,
                          { evidence: {} }
                        ])
        end

        # Re-reads the transition params, this time restricting the evidence
        # hash to only the fields allowed for the given target stage.
        def permitted_transition_params(stage_code)
          params.expect(candidate_workflow_transition: [
                          :to_stage_code,
                          :expected_current_stage_code,
                          :reason_code,
                          :note,
                          { evidence: permitted_evidence_fields(stage_code) }
                        ])
        end

        # Raises a validation error if the submitted evidence includes a
        # field that is not expected for the target stage.
        def validate_evidence_keys!(stage_code, evidence)
          return if evidence.blank? || !known_stage_code?(stage_code)

          field_name = ::CandidateWorkflows::StageRequirements.unexpected_fields_for(stage_code, evidence.to_h).first
          return if field_name.blank?

          raise ValidationError.new(
            field: "candidate_workflow_transition.evidence.#{field_name}",
            message: I18n.t('api.errors.workflow_transition_evidence_field_unexpected')
          )
        end

        # Raises a validation error when transitioning to the
        # documents-shared-with-Qatar-BU stage without the caller stating
        # which current stage they expect (an optimistic-concurrency guard).
        def validate_expected_current_stage_requirement!(raw_transition)
          return unless raw_transition[:to_stage_code].to_s.strip.downcase == 'documents_shared_with_qatar_bu'
          return if raw_transition[:expected_current_stage_code].present?

          raise ValidationError.new(
            field: 'candidate_workflow_transition.expected_current_stage_code',
            message: I18n.t('api.errors.workflow_transition_expected_stage_required')
          )
        end

        # Checks whether the given stage code matches one of the canonical
        # workflow stages.
        def known_stage_code?(stage_code)
          WorkflowStage::CANONICAL_STAGES.any? { |stage| stage[:code] == stage_code.to_s.strip.downcase }
        end

        # Looks up which evidence fields are allowed for the given target
        # stage, used to restrict the permitted evidence params.
        def permitted_evidence_fields(stage_code)
          ::CandidateWorkflows::StageRequirements.allowed_fields_for(stage_code)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
