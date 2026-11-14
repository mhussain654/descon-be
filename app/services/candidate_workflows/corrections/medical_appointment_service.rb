# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # Corrects the centre, address, date or time of a candidate's medical
    # appointment until they are medically fit or past the medical stages. The
    # original stage move is kept; the corrected values are saved as its
    # CandidateStageHistoryCorrection and shown wherever its details are read.
    class MedicalAppointmentService < BaseService
      private

      def blocked_reason = status.medical_blocked_reason
      def audited_record = status.medical_entry
      def action_code = 'medical_appointment_corrected'
      def sms_message_code = 'medical_appointment_changed'

      def apply!
        corrected = corrected_details
        changes = changed_fields(status.medical_entry.details.slice(*Status::MEDICAL_FIELDS), corrected)
        save_correction!(corrected) if changes.any?
        changes
      end

      def corrected_details
        name = text(:center_name)
        address = @values[:center_address].to_s.strip.presence
        date = text(:appointment_date)
        time = text(:appointment_time)
        validate_details!(name, address, date, time)
        { 'medical_center_name' => name, 'medical_center_address' => address,
          'medical_appointment_date' => date, 'medical_appointment_time' => time }
      end

      def validate_details!(name, address, date, time)
        validate_length!(:center_name, name, MedicalAppointmentSetting::CENTER_NAME_MAX_LENGTH)
        validate_length!(:center_address, address, MedicalAppointmentSetting::CENTER_ADDRESS_MAX_LENGTH)
        parse_date!(:appointment_date, date)
        validate_time!(:appointment_time, time)
      end

      def save_correction!(corrected)
        correction = status.medical_entry.correction || status.medical_entry.build_correction
        correction.update!(details: corrected, updated_by: @actor)
      end

      # The SMS names the date, so it is only sent when there is one.
      def sms_variables
        date = status.medical_entry.reload.details['medical_appointment_date']
        { date: CandidateSms::ScheduleDelivery.format_date(Date.iso8601(date)) } if date.present?
      end
    end
  end
end
