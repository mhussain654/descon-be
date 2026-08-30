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

    def validate_field_value!(field_name, value)
      case StageRequirements.field_type_for(@destination_stage.code, field_name)
      when :iso_date
        validate_iso_date!(field_name, value)
      when :string
        validate_string!(field_name, value)
      when Hash
        validate_enum!(field_name, value)
      end
    end

    def validate_iso_date!(field_name, value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      raise ValidationError.new(
        field: evidence_field(field_name),
        message: I18n.t('api.errors.workflow_transition_evidence_date_invalid')
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
