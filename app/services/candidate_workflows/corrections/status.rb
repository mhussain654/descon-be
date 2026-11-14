# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # What a developer may correct for a candidate right now -- the medical
    # appointment, the QVC appointment and the flight details -- with each one's
    # current values, whether it can be changed, and if not, why
    # (`blocked_reason`). Read by the Overview tab and checked again by each
    # correction service before it changes anything.
    class Status
      BLOCKED_NOT_RECORDED = 'not_recorded'
      BLOCKED_PAST_MEDICAL = 'past_medical'
      BLOCKED_QVC_RESULT_RECORDED = 'qvc_result_recorded'
      BLOCKED_MOBILIZED = 'mobilized'
      PAKISTAN_TIME_ZONE = 'Asia/Karachi'
      MEDICAL_FIELDS = %w[medical_center_name medical_center_address medical_appointment_date
                          medical_appointment_time].freeze

      def initialize(assignment)
        @assignment = assignment
      end

      def medical_entry
        return if @assignment.blank?

        @medical_entry ||= @assignment.candidate_stage_histories
                                      .where(stage_code: StageRequirements::MEDICAL_APPOINTMENT_STAGE_CODES)
                                      .order(:occurred_at, :id).last
      end

      def qvc_attempt
        return if @assignment.blank?

        @qvc_attempt ||= @assignment.candidate_qvc_attempts.latest_first.first
      end

      def flight_detail = @assignment&.candidate_flight_detail

      def medical_blocked_reason
        return BLOCKED_NOT_RECORDED if medical_entry.blank?

        BLOCKED_PAST_MEDICAL if past_medical?
      end

      def qvc_blocked_reason
        return BLOCKED_NOT_RECORDED if qvc_attempt.blank?

        BLOCKED_QVC_RESULT_RECORDED if qvc_attempt.completed?
      end

      def flight_blocked_reason
        return BLOCKED_NOT_RECORDED if flight_detail.blank?

        BLOCKED_MOBILIZED if flight_detail.mobilized? || @assignment.current_workflow_stage&.code == 'mobilized'
      end

      def medical_values
        details = medical_entry&.details.to_h
        {
          center_name: details['medical_center_name'], center_address: details['medical_center_address'],
          appointment_date: details['medical_appointment_date'], appointment_time: details['medical_appointment_time']
        }
      end

      def qvc_values
        attempt = qvc_attempt
        {
          attempt_number: attempt&.attempt_number, appointment_date: attempt&.appointment_date&.iso8601,
          appointment_time: attempt&.appointment_time, center_name: attempt&.center_name,
          center_address: attempt&.center_address
        }
      end

      def flight_values
        detail = flight_detail
        {
          airline: detail&.airline, flight_number: detail&.flight_number, sector: detail&.sector,
          flight_date: detail && detail.flight_departure_at.in_time_zone(PAKISTAN_TIME_ZONE).iso8601,
          has_ticket: detail.present? && detail.ticket.attached?
        }
      end

      private

      # Medically fit, or moved on beyond the process's medical stages (an unfit
      # candidate is held at the result stage, so may still be rebooked).
      def past_medical?
        return true if @assignment.candidate_medical_results.latest_first.first&.fit?

        current_position = @assignment.current_mobilization_process_stage&.position
        last_medical_position = medical_process_positions.max
        current_position.present? && last_medical_position.present? && current_position > last_medical_position
      end

      def medical_process_positions
        codes = StageRequirements::MEDICAL_APPOINTMENT_STAGE_CODES + StageRequirements::MEDICAL_OUTCOME_STAGE_CODES
        @assignment.mobilization_process.stages.includes(:workflow_stage)
                   .select { |stage| codes.include?(stage.code) }.map(&:position)
      end
    end
  end
end
