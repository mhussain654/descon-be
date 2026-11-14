# frozen_string_literal: true

module CandidateWorkflows
  module QvcAttempts
    # rubocop:disable Metrics/ClassLength
    class ScheduleService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :appointment_date,
        :center_name,
        :center_address,
        :appointment_time,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          appointment_date: params[:appointment_date].to_s,
          **normalized_place_and_time(params),
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_appointment_date!
        validate_appointment_time!

        CandidateAssignment.transaction do
          schedule_attempt!
        end
      end

      private

      def normalized_place_and_time(params)
        { center_name: params[:center_name].to_s.squish.presence,
          center_address: params[:center_address].to_s.strip.presence,
          appointment_time: params[:appointment_time].to_s.strip.presence }
      end

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

      def validate_appointment_time!
        return if @params.appointment_time.nil? || @params.appointment_time.match?(QvcAppointmentSetting::TIME_FORMAT)

        raise ValidationError.new(
          field: 'candidate_qvc_attempt.appointment_time',
          message: I18n.t('api.errors.workflow_transition_evidence_value_invalid')
        )
      end

      # The centre, address and time, leaving out any not given.
      def place_and_time
        { center_name: @params.center_name, center_address: @params.center_address,
          appointment_time: @params.appointment_time }.compact
      end

      def place_and_time_evidence = place_and_time.transform_keys { |key| :"qvc_#{key}" }

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
          evidence: { appointment_date: @params.appointment_date, **place_and_time_evidence }
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
          scheduled_by: @params.actor, attempt_number: next_attempt_number(assignment),
          appointment_date: Date.iso8601(@params.appointment_date), internal_note: @params.note, **place_and_time
        )
        assignment.update!(updated_at: Time.current)
        record_follow_up!(assignment, attempt)
        attempt
      end

      # A follow-up is booked without a stage change, so its SMS is queued here.
      def record_follow_up!(assignment, attempt)
        record_attempt_audit!(assignment, attempt)
        CandidateSms::ScheduleDelivery.call(assignment:, **CandidateSms::StageMessage.qvc_appointment(attempt))
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
