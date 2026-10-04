# frozen_string_literal: true

module CandidateWorkflows
  module MedicalResults
    # Records a medical result (fit/unfit) for a candidate. When their next
    # process stage is the medical-outcome stage, this is the transition into
    # it (the result is recorded as a side effect); while an unfit candidate is
    # held at that stage, it records a re-decision (e.g. after a re-medical)
    # with no transition. Only a fit latest result lets the candidate move on.
    class RecordService < ApplicationService
      Params = Struct.new(:actor, :candidate, :outcome_code, :result_date, :note, :expected_current_stage_code,
                          :request_id, keyword_init: true)

      def initialize(**params)
        @params = Params.new(**params, outcome_code: params[:outcome_code].to_s.strip.downcase.presence,
                                       note: params[:note].to_s.strip.presence)
      end

      def call
        validate_actor!
        validate_expected_stage!
        CandidateAssignment.transaction { held_at_medical_outcome? ? record_re_decision! : transition_into_outcome! }
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_expected_stage!
        return if @params.expected_current_stage_code.to_s.strip.present?

        raise ValidationError.new(field: 'candidate_medical_result.expected_current_stage_code',
                                  message: I18n.t('api.errors.expected_current_stage_code_required'))
      end

      def locked_assignment
        return @locked_assignment if defined?(@locked_assignment)

        candidate = Candidate.lock.find(@params.candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        @locked_assignment = CandidateAssignment.lock.find(assignment_id)
      end

      def held_at_medical_outcome?
        locked_assignment.current_mobilization_process_stage.action_type == 'medical_outcome'
      end

      # The first result moves the candidate into their process's medical-outcome
      # stage; any other next stage means there's no medical result to record now.
      def transition_into_outcome!
        result = TransitionService.call(
          actor: @params.actor, candidate: @params.candidate, to_stage_code: outcome_stage_code,
          expected_current_stage_code: @params.expected_current_stage_code, request_id: @params.request_id,
          note: @params.note, evidence: evidence
        )
        { medical_result: latest_result, snapshot: result.fetch(:snapshot) }
      end

      def outcome_stage_code
        next_stage = locked_assignment.next_process_stage
        unless next_stage&.action_type == 'medical_outcome'
          raise InvalidWorkflowTransitionError.new(field: 'candidate_medical_result.outcome_code')
        end

        WorkflowStage.where(id: next_stage.workflow_stage_id).pick(:code)
      end

      def record_re_decision!
        ExpectedStageValidator.call(current_stage: locked_assignment.current_workflow_stage,
                                    expected_current_stage_code: @params.expected_current_stage_code)
        validate_result!
        medical_result = locked_assignment.candidate_medical_results.create!(re_decision_attributes)
        locked_assignment.update!(updated_at: Time.current)
        audit!(medical_result)
        { medical_result:, snapshot: StateSnapshotService.call(candidate: @params.candidate) }
      end

      def audit!(medical_result)
        MedicalResultAuditRecorder.call(actor: @params.actor, request_id: @params.request_id,
                                        context: audit_context(medical_result))
      end

      def re_decision_attributes
        { recorded_by: @params.actor, outcome_code: @params.outcome_code,
          result_date: Date.iso8601(@params.result_date.to_s), note: @params.note }
      end

      def audit_context(medical_result)
        { candidate: @params.candidate, assignment: locked_assignment, result: medical_result }
      end

      def latest_result = locked_assignment.candidate_medical_results.latest_first.first

      def evidence
        { 'medical_outcome_code' => @params.outcome_code, 'medical_result_date' => @params.result_date.to_s }
      end

      # The same rules the transition applies to its evidence.
      def validate_result!
        EvidenceValidator.call(destination_stage: locked_assignment.current_workflow_stage, evidence:)
        return if @params.outcome_code.present? && @params.result_date.present?

        raise ValidationError.new(field: 'candidate_medical_result.outcome_code',
                                  message: I18n.t('api.errors.validation_failed'))
      end
    end
  end
end
