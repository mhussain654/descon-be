# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # Corrects the date, time, centre or address of a candidate's latest QVC
    # booking until its result (or a no-show) is recorded.
    class QvcAppointmentService < BaseService
      private

      def blocked_reason = status.qvc_blocked_reason
      def audited_record = status.qvc_attempt
      def action_code = 'qvc_appointment_corrected'
      def sms_message_code = 'qvc_appointment_changed'

      def apply!
        attempt = status.qvc_attempt
        corrected = corrected_values
        changes = changed_fields(current_values(attempt), corrected)
        attempt.update!(corrected.merge('appointment_date' => Date.iso8601(corrected['appointment_date'])))
        changes
      end

      def current_values(attempt)
        { 'appointment_date' => attempt.appointment_date.iso8601, 'appointment_time' => attempt.appointment_time,
          'center_name' => attempt.center_name, 'center_address' => attempt.center_address }
      end

      def corrected_values
        values = { 'appointment_date' => text(:appointment_date), 'appointment_time' => text(:appointment_time),
                   'center_name' => text(:center_name), 'center_address' => address }
        parse_date!(:appointment_date, values['appointment_date'], required: true)
        validate_time!(:appointment_time, values['appointment_time'])
        validate_length!(:center_name, values['center_name'], QvcAppointmentSetting::CENTER_NAME_MAX_LENGTH)
        validate_length!(:center_address, values['center_address'], QvcAppointmentSetting::CENTER_ADDRESS_MAX_LENGTH)
        values
      end

      def address = @values[:center_address].to_s.strip.presence

      def sms_variables
        { date: CandidateSms::ScheduleDelivery.format_date(status.qvc_attempt.appointment_date) }
      end
    end
  end
end
