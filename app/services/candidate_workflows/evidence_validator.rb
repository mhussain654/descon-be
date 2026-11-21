# frozen_string_literal: true

module CandidateWorkflows
  class EvidenceValidator < ApplicationService
    def initialize(destination_stage:, evidence:)
      @destination_stage = destination_stage
      @evidence = evidence
    end

    def call
      validate_unexpected_fields!
      validate_field_values!
    end

    private

    def validate_unexpected_fields!
      unexpected_field = StageRequirements.unexpected_fields_for(@destination_stage.code, @evidence).first
      return if unexpected_field.blank?

      raise ValidationError.new(
        field: evidence_field(unexpected_field),
        message: I18n.t('api.errors.workflow_transition_evidence_field_unexpected')
      )
    end

    def validate_field_values!
      @evidence.each do |field_name, value|
        validate_field_value!(field_name, value)
      end
    end

    VALUE_VALIDATORS = {
      iso_date: :validate_iso_date!, iso_datetime: :validate_iso_datetime!, time: :validate_time!,
      string: :validate_string!
    }.freeze
    private_constant :VALUE_VALIDATORS

    def validate_field_value!(field_name, value)
      field_type = StageRequirements.field_type_for(@destination_stage.code, field_name)
      return validate_enum!(field_name, value) if field_type.is_a?(Hash)

      validator = VALUE_VALIDATORS[field_type]
      send(validator, field_name, value) if validator
    end

    # Evidence dates that record something that has already happened.
    PAST_ONLY_DATE_FIELDS = %w[mobilized_on].freeze
    private_constant :PAST_ONLY_DATE_FIELDS

    def validate_iso_date!(field_name, value)
      date = Date.iso8601(value.to_s)
      validate_not_in_future!(field_name, date) if PAST_ONLY_DATE_FIELDS.include?(field_name)
    rescue ArgumentError
      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_date_invalid')
      )
    end

    def validate_not_in_future!(field_name, date)
      return if date <= CandidateFlightDetail.pakistan_today

      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.flight_mobilization_date_in_future')
      )
    end

    def validate_iso_datetime!(field_name, value)
      DateTime.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_date_invalid')
      )
    end

    def validate_time!(field_name, value)
      return if value.is_a?(String) && value.match?(MedicalAppointmentSetting::TIME_FORMAT)

      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_time_invalid')
      )
    end

    def validate_string!(field_name, value)
      return if value.is_a?(String) && value.present?

      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_value_invalid')
      )
    end

    def validate_enum!(field_name, value)
      return if StageRequirements.enum_values_for(@destination_stage.code, field_name).include?(value)

      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_enum_invalid')
      )
    end

    def evidence_field(field_name)
      "candidate_workflow_transition.evidence.#{field_name}"
    end
  end
end
