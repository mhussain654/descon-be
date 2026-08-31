# frozen_string_literal: true

module CandidateWorkflows
  module QvcAttempts
    # rubocop:disable Metrics/ClassLength
    class ScheduleService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :appointment_date,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          appointment_date: params[:appointment_date].to_s,
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_appointment_date!

        CandidateAssignment.transaction do
          schedule_attempt!
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_appointment_date!
        Date.iso8601(@params.appointment_date)
      rescue ArgumentError
        raise ValidationError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          message: I18n.t('api.errors.workflow_transition_evidence_date_invalid')
        )
      end

      def locked_assignment
        candidate = Candidate.lock.find(@params.candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        CandidateAssignment.lock.includes(:current_workflow_stage).find(assignment_id)
      end

      def initial_transition_stage?(current_stage)
        current_stage.code == 'documents_shared_with_qatar_bu'
      end

      def initial_transition_result
        TransitionService.call(
          actor: @params.actor,
          candidate: @params.candidate,
          to_stage_code: 'qvc_appointment_booked',
          expected_current_stage_code: @params.expected_current_stage_code,
          request_id: @params.request_id,
          note: @params.note,
          evidence: { appointment_date: @params.appointment_date }
        )
      end

      def validate_follow_up_stage!(assignment:, current_stage:)
        latest_attempt = assignment.candidate_qvc_attempts.latest_first.first
        return if reopen_after_no_show?(current_stage, latest_attempt)
        return if follow_up_after_re_medical?(current_stage, latest_attempt)

        raise InvalidWorkflowTransitionError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          details: { current_stage_code: current_stage.code }
        )
      end

      def reopen_after_no_show?(current_stage, latest_attempt)
        current_stage.code == 'qvc_appointment_booked' && latest_attempt&.no_show?
      end

      def follow_up_after_re_medical?(current_stage, latest_attempt)
        current_stage.code == 'qvc_completed_outcome_received' && latest_attempt&.outcome_code == 're_medical'
      end

      def ensure_no_open_attempt!(assignment)
        return unless assignment.candidate_qvc_attempts.open_attempts.exists?

        raise ValidationError.new(
          field: 'candidate_qvc_attempt.appointment_date',
          message: I18n.t('api.errors.qvc_open_attempt_exists')
        )
      end

      def create_follow_up_attempt!(assignment)
        ensure_no_open_attempt!(assignment)

        attempt = assignment.candidate_qvc_attempts.create!(
          scheduled_by: @params.actor,
          attempt_number: next_attempt_number(assignment),
          appointment_date: Date.iso8601(@params.appointment_date),
          internal_note: @params.note
        )
        assignment.update!(updated_at: Time.current)
        record_attempt_audit!(assignment, attempt)
        attempt
      end

      def next_attempt_number(assignment)
        assignment.candidate_qvc_attempts.maximum(:attempt_number).to_i + 1
      end

      def record_attempt_audit!(assignment, attempt)
        QvcAttemptAuditRecorder.call(
          event: :scheduled,
          actor: @params.actor,
          request_id: @params.request_id,
          context: { candidate: @params.candidate, assignment:, attempt: }
        )
      end

      def schedule_attempt!
        assignment = locked_assignment
        current_stage = assignment.current_workflow_stage
        validate_expected_stage!(current_stage)
        return initial_transition_result if initial_transition_stage?(current_stage)

        validate_follow_up_stage!(assignment:, current_stage:)
        attempt_result(create_follow_up_attempt!(assignment))
      end

      def validate_expected_stage!(current_stage)
        ExpectedStageValidator.call(
          current_stage:,
          expected_current_stage_code: @params.expected_current_stage_code
        )
      end

      def attempt_result(attempt)
        {
          qvc_attempt: attempt,
          snapshot: StateSnapshotService.call(candidate: @params.candidate)
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
