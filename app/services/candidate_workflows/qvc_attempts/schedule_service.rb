# frozen_string_literal: true

module CandidateWorkflows
  module QvcAttempts
    class ScheduleService < ApplicationService
      def initialize(actor:, candidate:, appointment_date:, expected_current_stage_code:, request_id:, note: nil)
        @actor = actor
        @candidate = candidate
        @appointment_date = appointment_date.to_s
        @expected_current_stage_code = expected_current_stage_code
        @request_id = request_id
        @note = note.to_s.strip.presence
      end

      def call
        validate_actor!
        validate_appointment_date!

        CandidateAssignment.transaction do
          assignment = locked_assignment
          current_stage = assignment.current_workflow_stage
          ExpectedStageValidator.call(current_stage:, expected_current_stage_code: @expected_current_stage_code)

          if current_stage.code == 'documents_shared_with_qatar_bu'
            return TransitionService.call(
              actor: @actor,
              candidate: @candidate,
              to_stage_code: 'qvc_appointment_booked',
              expected_current_stage_code: @expected_current_stage_code,
              request_id: @request_id,
              note: @note,
              evidence: { appointment_date: @appointment_date }
            )
          end

          validate_follow_up_stage!(assignment:, current_stage:)
          ensure_no_open_attempt!(assignment)
          attempt = assignment.candidate_qvc_attempts.create!(
            scheduled_by: @actor,
            attempt_number: assignment.candidate_qvc_attempts.maximum(:attempt_number).to_i + 1,
            appointment_date: Date.iso8601(@appointment_date),
            internal_note: @note
          )
          assignment.update!(updated_at: Time.current)
          QvcAttemptAuditRecorder.call(
            event: :scheduled,
            candidate: @candidate,
            assignment:,
            attempt:,
            actor: @actor,
            request_id: @request_id
          )

          {
            qvc_attempt: attempt,
            snapshot: StateSnapshotService.call(candidate: @candidate)
          }
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('manage_workflow')
      end

      def validate_appointment_date!
        Date.iso8601(@appointment_date)
      rescue ArgumentError
        raise ValidationError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          message: I18n.t('api.errors.workflow_transition_evidence_date_invalid')
        )
      end

      def locked_assignment
        candidate = Candidate.lock.find(@candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        CandidateAssignment.lock.includes(:current_workflow_stage).find(assignment_id)
      end

      def validate_follow_up_stage!(assignment:, current_stage:)
        if current_stage.code == 'qvc_appointment_booked'
          latest_attempt = assignment.candidate_qvc_attempts.latest_first.first
          return if latest_attempt&.no_show?
        elsif current_stage.code == 'qvc_completed_outcome_received'
          latest_attempt = assignment.candidate_qvc_attempts.latest_first.first
          return if latest_attempt&.outcome_code == 're_medical'
        end

        raise InvalidWorkflowTransitionError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          details: { current_stage_code: current_stage.code }
        )
      end

      def ensure_no_open_attempt!(assignment)
        return unless assignment.candidate_qvc_attempts.open_attempts.exists?

        raise ValidationError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          message: I18n.t('api.errors.qvc_open_attempt_exists')
        )
      end
    end
  end
end
