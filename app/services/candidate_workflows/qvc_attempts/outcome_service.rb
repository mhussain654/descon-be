# frozen_string_literal: true

module CandidateWorkflows
  module QvcAttempts
    class OutcomeService < ApplicationService
      def initialize(actor:, candidate:, qvc_attempt_public_id:, outcome_code:, no_show:, expected_current_stage_code:,
                     request_id:, note: nil)
        @actor = actor
        @candidate = candidate
        @qvc_attempt_public_id = qvc_attempt_public_id
        @outcome_code = normalized_outcome_code(outcome_code)
        @no_show = no_show.nil? ? false : ActiveModel::Type::Boolean.new.cast(no_show)
        @expected_current_stage_code = expected_current_stage_code
        @request_id = request_id
        @note = note.to_s.strip.presence
      end

      def call
        validate_actor!
        validate_outcome_payload!

        CandidateAssignment.transaction do
          assignment = locked_assignment
          current_stage = assignment.current_workflow_stage
          ExpectedStageValidator.call(current_stage:, expected_current_stage_code: @expected_current_stage_code)
          attempt = lock_attempt!(assignment)

          if current_stage.code == 'qvc_appointment_booked' && !@no_show
            return TransitionService.call(
              actor: @actor,
              candidate: @candidate,
              to_stage_code: 'qvc_completed_outcome_received',
              expected_current_stage_code: @expected_current_stage_code,
              request_id: @request_id,
              note: @note,
              evidence: { qvc_outcome_code: @outcome_code }
            )
          end

          validate_direct_outcome_stage!(current_stage)
          complete_attempt_without_transition!(assignment, attempt)
          {
            qvc_attempt: attempt.reload,
            snapshot: StateSnapshotService.call(candidate: @candidate)
          }
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('manage_workflow')
      end

      def validate_outcome_payload!
        if @no_show && @outcome_code.present?
          raise ValidationError.new(
            field: 'candidate_qvc_attempt.outcome_code',
            message: I18n.t('api.errors.qvc_no_show_outcome_conflict')
          )
        end
        validate_supported_outcome_code! if @outcome_code.present?
        return if @no_show || @outcome_code.present?

        raise ValidationError.new(
          field: 'candidate_qvc_attempt.outcome_code',
          message: I18n.t('api.errors.qvc_outcome_required')
        )
      end

      def locked_assignment
        candidate = Candidate.lock.find(@candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        CandidateAssignment.lock.includes(:current_workflow_stage).find(assignment_id)
      end

      def lock_attempt!(assignment)
        attempt = assignment.candidate_qvc_attempts.lock.find_by!(public_id: @qvc_attempt_public_id)
        raise ValidationError.new(field: 'candidate_qvc_attempt.id', message: I18n.t('api.errors.qvc_attempt_closed')) if attempt.completed?

        attempt
      end

      def validate_direct_outcome_stage!(current_stage)
        return if current_stage.code == 'qvc_appointment_booked' && @no_show
        return if current_stage.code == 'qvc_completed_outcome_received'

        raise InvalidWorkflowTransitionError.new(
          field: 'candidate_qvc_attempt.outcome_code',
          details: { current_stage_code: current_stage.code }
        )
      end

      def complete_attempt_without_transition!(assignment, attempt)
        recorded_at = Time.current
        attempt.update!(
          outcome_code: @outcome_code,
          no_show: @no_show,
          outcome_recorded_at: recorded_at,
          outcome_recorded_by: @actor,
          internal_note: @note
        )
        update_assignment_qvc_summary!(assignment, recorded_at)
        QvcAttemptAuditRecorder.call(
          event: :completed,
          candidate: @candidate,
          assignment:,
          attempt:,
          actor: @actor,
          request_id: @request_id
        )
      end

      def normalized_outcome_code(value)
        value.to_s.strip.downcase.presence
      end

      def validate_supported_outcome_code!
        return if CandidateQvcAttempt::OUTCOME_CODES.include?(@outcome_code)

        raise ValidationError.new(
          field: 'candidate_qvc_attempt.outcome_code',
          message: I18n.t('api.errors.workflow_transition_evidence_enum_invalid')
        )
      end

      def update_assignment_qvc_summary!(assignment, recorded_at)
        attributes = { updated_at: recorded_at }
        if @outcome_code.present?
          attributes[:qvc_outcome_code] = @outcome_code
          attributes[:qvc_outcome_date] = recorded_at.to_date
        end
        assignment.update!(attributes)
      end
    end
  end
end
