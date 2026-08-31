# frozen_string_literal: true

module CandidateWorkflows
  module StageRequirements
    QVC_OUTCOME_CODES = %w[approved re_medical rejected].freeze
    VISA_OUTCOME_CODES = %w[issued rejected].freeze
    VISA_REJECTION_REASON_CODES = %w[
      document_discrepancy medical_issue security_clearance embassy_rejection incomplete_application other
    ].freeze

    STAGE_RULES = {
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
      'protected_ready_to_fly' => {
        required_fields: %w[protected_on],
        allowed_fields: %w[protected_on],
        field_types: { 'protected_on' => :iso_date }
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

    def rule_for(stage_code)
      STAGE_RULES.fetch(stage_code.to_s, {})
    end
  end
end
