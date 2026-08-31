# frozen_string_literal: true

module CandidateWorkflows
  module QvcAttempts
    # rubocop:disable Metrics/ClassLength
    class OutcomeService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :qvc_attempt_public_id,
        :outcome_code,
        :no_show,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          outcome_code: normalized_outcome_code(params[:outcome_code]),
          no_show: normalized_no_show(params[:no_show]),
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_outcome_payload!

        CandidateAssignment.transaction do
          process_outcome!
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_outcome_payload!
        raise_no_show_conflict! if no_show_conflict?
        validate_supported_outcome_code! if @params.outcome_code.present?
        return if @params.no_show || @params.outcome_code.present?

        raise_validation_error('candidate_qvc_attempt.outcome_code', 'api.errors.qvc_outcome_required')
      end

      def locked_assignment
        candidate = Candidate.lock.find(@params.candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        CandidateAssignment.lock.includes(:current_workflow_stage).find(assignment_id)
      end

      def lock_attempt!(assignment)
        attempt = assignment.candidate_qvc_attempts.lock.find_by!(public_id: @params.qvc_attempt_public_id)
        raise_closed_attempt_error! if attempt.completed?

        attempt
      end

      def validate_direct_outcome_stage!(current_stage)
        return if current_stage.code == 'qvc_appointment_booked' && @params.no_show
        return if current_stage.code == 'qvc_completed_outcome_received'

        raise InvalidWorkflowTransitionError.new(
          field: 'candidate_qvc_attempt.outcome_code',
          details: { current_stage_code: current_stage.code }
        )
      end

      def complete_attempt_without_transition!(assignment:, attempt:)
        recorded_at = Time.current
        attempt.update!(attempt_completion_attributes(recorded_at))
        update_assignment_qvc_summary!(assignment, recorded_at)
        record_attempt_audit!(assignment:, attempt:)
      end

      def normalized_outcome_code(value)
        value.to_s.strip.downcase.presence
      end

      def normalized_no_show(value)
        value.nil? ? false : ActiveModel::Type::Boolean.new.cast(value)
      end

      def transition_stage?(current_stage)
        current_stage.code == 'qvc_appointment_booked' && !@params.no_show
      end

      def transition_result
        TransitionService.call(
          actor: @params.actor,
          candidate: @params.candidate,
          to_stage_code: 'qvc_completed_outcome_received',
          expected_current_stage_code: @params.expected_current_stage_code,
          request_id: @params.request_id,
          note: @params.note,
          evidence: { qvc_outcome_code: @params.outcome_code }
        )
      end

      def no_show_conflict?
        @params.no_show && @params.outcome_code.present?
      end

      def raise_no_show_conflict!
        raise_validation_error('candidate_qvc_attempt.outcome_code', 'api.errors.qvc_no_show_outcome_conflict')
      end

      def validate_supported_outcome_code!
        return if CandidateQvcAttempt::OUTCOME_CODES.include?(@params.outcome_code)

        raise_validation_error(
          'candidate_qvc_attempt.outcome_code',
          'api.errors.workflow_transition_evidence_enum_invalid'
        )
      end

      def update_assignment_qvc_summary!(assignment, recorded_at)
        attributes = { updated_at: recorded_at }
        if @params.outcome_code.present?
          attributes[:qvc_outcome_code] = @params.outcome_code
          attributes[:qvc_outcome_date] = recorded_at.to_date
        end
        assignment.update!(attributes)
      end

      def raise_closed_attempt_error!
        raise_validation_error('candidate_qvc_attempt.id', 'api.errors.qvc_attempt_closed')
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def process_outcome!
        assignment = locked_assignment
        current_stage = assignment.current_workflow_stage
        validate_expected_stage!(current_stage)
        attempt = lock_attempt!(assignment)
        return transition_result if transition_stage?(current_stage)

        validate_direct_outcome_stage!(current_stage)
        complete_attempt_without_transition!(assignment:, attempt:)
        outcome_result(attempt)
      end

      def validate_expected_stage!(current_stage)
        ExpectedStageValidator.call(
          current_stage:,
          expected_current_stage_code: @params.expected_current_stage_code
        )
      end

      def attempt_completion_attributes(recorded_at)
        {
          outcome_code: @params.outcome_code,
          no_show: @params.no_show,
          outcome_recorded_at: recorded_at,
          outcome_recorded_by: @params.actor,
          internal_note: @params.note
        }
      end

      def record_attempt_audit!(assignment:, attempt:)
        QvcAttemptAuditRecorder.call(
          event: :completed,
          actor: @params.actor,
          request_id: @params.request_id,
          context: { candidate: @params.candidate, assignment:, attempt: }
        )
      end

      def outcome_result(attempt)
        {
          qvc_attempt: attempt.reload,
          snapshot: StateSnapshotService.call(candidate: @params.candidate)
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
