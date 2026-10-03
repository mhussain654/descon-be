# frozen_string_literal: true

module CandidateWorkflows
  # The evidence each destination stage accepts and requires, by stage code. A
  # stage absent here takes no evidence. Fields are dates (`iso_date`),
  # datetimes, non-blank strings or enums; `allowed_fields` beyond
  # `required_fields` are optional.
  # rubocop:disable Metrics/ModuleLength
  module StageRequirements
    QVC_OUTCOME_CODES = %w[approved re_medical rejected].freeze
    MEDICAL_OUTCOME_CODES = CandidateMedicalResult::OUTCOME_CODES
    PROTECTION_CALL_STATUSES = %w[scheduled completed].freeze
    VISA_OUTCOME_CODES = %w[issued rejected].freeze
    VISA_REJECTION_REASON_CODES = %w[
      document_discrepancy medical_issue security_clearance embassy_rejection incomplete_application other
    ].freeze

    MEDICAL_APPOINTMENT_RULE = {
      required_fields: [],
      allowed_fields: %w[medical_appointment_date],
      field_types: { 'medical_appointment_date' => :iso_date }
    }.freeze

    MEDICAL_OUTCOME_RULE = {
      required_fields: %w[medical_outcome_code medical_result_date],
      allowed_fields: %w[medical_outcome_code medical_result_date],
      field_types: {
        'medical_outcome_code' => { type: :enum, values: MEDICAL_OUTCOME_CODES },
        'medical_result_date' => :iso_date
      }
    }.freeze

    STAGE_RULES = {
      'medical_pending' => MEDICAL_APPOINTMENT_RULE,
      'medical_appointment' => MEDICAL_APPOINTMENT_RULE,
      'gamca_medical_pending' => MEDICAL_APPOINTMENT_RULE,
      'medical_completed' => MEDICAL_OUTCOME_RULE,
      'medical_fit' => MEDICAL_OUTCOME_RULE,
      'gamca_medical_completed' => MEDICAL_OUTCOME_RULE,
      'e_number_received' => {
        required_fields: %w[e_number e_number_received_on],
        allowed_fields: %w[e_number e_number_received_on],
        field_types: { 'e_number' => :string, 'e_number_received_on' => :iso_date }
      },
      'biometric_completed' => {
        required_fields: %w[biometric_completed_on],
        allowed_fields: %w[biometric_completed_on],
        field_types: { 'biometric_completed_on' => :iso_date }
      },
      'protection_call' => {
        required_fields: %w[protection_call_status protection_call_on],
        allowed_fields: %w[protection_call_status protection_call_on],
        field_types: {
          'protection_call_status' => { type: :enum, values: PROTECTION_CALL_STATUSES },
          'protection_call_on' => :iso_date
        }
      },
      'ticket_handover' => {
        required_fields: %w[ticket_handed_over_on],
        allowed_fields: %w[ticket_handed_over_on ticket_reference],
        field_types: { 'ticket_handed_over_on' => :iso_date, 'ticket_reference' => :string }
      },
      'qvc_appointment_booked' => {
        required_fields: %w[appointment_date],
        allowed_fields: %w[appointment_date],
        field_types: { 'appointment_date' => :iso_date }
      },
      'qvc_completed_outcome_received' => {
        required_fields: %w[qvc_outcome_code],
        allowed_fields: %w[qvc_outcome_code],
        field_types: {
          'qvc_outcome_code' => { type: :enum, values: QVC_OUTCOME_CODES }
        }
      },
      'visa_issued_or_rejected' => {
        required_fields: %w[visa_outcome_code visa_outcome_date],
        allowed_fields: %w[visa_outcome_code visa_outcome_date rejection_reason_code],
        field_types: {
          'visa_outcome_code' => { type: :enum, values: VISA_OUTCOME_CODES },
          'visa_outcome_date' => :iso_date,
          'rejection_reason_code' => { type: :enum, values: VISA_REJECTION_REASON_CODES }
        }
      },
      'appeared_for_protection' => {
        required_fields: %w[appeared_for_protection_on],
        allowed_fields: %w[appeared_for_protection_on],
        field_types: { 'appeared_for_protection_on' => :iso_date }
      },
      'flight_details_uploaded' => {
        required_fields: %w[airline flight_reference sector flight_date],
        allowed_fields: %w[airline flight_reference sector flight_date],
        field_types: {
          'airline' => :string,
          'flight_reference' => :string,
          'sector' => :string,
          'flight_date' => :iso_datetime
        }
      },
      'mobilized' => {
        required_fields: %w[mobilized_on],
        allowed_fields: %w[mobilized_on],
        field_types: { 'mobilized_on' => :iso_date }
      }
    }.freeze

    module_function

    def required_fields_for(stage_code)
      rule_for(stage_code).fetch(:required_fields, [])
    end

    def allowed_fields_for(stage_code)
      rule_for(stage_code).fetch(:allowed_fields, [])
    end

    def field_type_for(stage_code, field_name)
      rule_for(stage_code).dig(:field_types, field_name.to_s)
    end

    def enum_values_for(stage_code, field_name)
      field_type = field_type_for(stage_code, field_name)
      return [] unless field_type.is_a?(Hash) && field_type[:type] == :enum

      field_type.fetch(:values)
    end

    def unexpected_fields_for(stage_code, evidence)
      evidence.keys.map(&:to_s) - allowed_fields_for(stage_code)
    end

    def required_field_blocking_reasons_for(stage_code)
      required_fields_for(stage_code).map { |field_name| "#{field_name}_required" }
    end

    def field_required_blocking_reason(field_name)
      "#{field_name}_required"
    end

    # Every accepted field as `{ name:, type:, required:, values: }` (values only
    # for enums) -- what a client needs to build the transition form.
    def fields_for(stage_code)
      required = required_fields_for(stage_code)
      allowed_fields_for(stage_code).map do |field_name|
        field_type = field_type_for(stage_code, field_name)
        type = field_type.is_a?(Hash) ? field_type.fetch(:type) : field_type
        { name: field_name, type: type.to_s, required: required.include?(field_name),
          values: field_type.is_a?(Hash) ? field_type.fetch(:values) : nil }.compact
      end
    end

    def rule_for(stage_code)
      STAGE_RULES.fetch(stage_code.to_s, {})
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
