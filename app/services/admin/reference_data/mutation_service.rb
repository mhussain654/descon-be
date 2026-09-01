# frozen_string_literal: true

module Admin
  module ReferenceData
    # Owns the administrative lifecycle of assignment lookup values. Codes are
    # stable identifiers and intentionally cannot be changed after creation.
    class MutationService < ApplicationService
      Params = Struct.new(:actor, :record, :record_class, :action, :attributes, :expected_updated_at, :request_id,
                          keyword_init: true)

      def initialize(**params)
        @params = Params.new(**params)
      end

      def call
        validate_actor!

        @params.record_class.transaction do
          @record = locked_record
          validate_staleness!
          apply_mutation!
          record_audit!
          @record
        end
      rescue ActiveRecord::RecordNotUnique
        raise ValidationError.new(field: 'code', message: I18n.t('api.errors.reference_data_code_taken'))
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_candidates')
      end

      def locked_record
        return @params.record.lock! if @params.record.present?

        @params.record_class.new
      end

      def validate_staleness!
        return if @params.action == :create || @params.expected_updated_at.blank?

        expected = Time.iso8601(@params.expected_updated_at.to_s)
        raise StaleReferenceDataError unless expected.to_i == @record.updated_at.to_i
      rescue ArgumentError
        raise ValidationError.new(field: 'expected_updated_at', message: I18n.t('api.errors.validation_failed'))
      end

      def apply_mutation!
        case @params.action
        when :create
          @record.assign_attributes(create_attributes)
          @record.save!
        when :update then @record.update!(update_attributes)
        when :retire then @record.update!(active: false)
        else raise ArgumentError, "unsupported reference-data action: #{@params.action}"
        end
      end

      def create_attributes
        normalized_attributes.merge(active: true)
      end

      def update_attributes
        normalized_attributes.except(:code)
      end

      def normalized_attributes
        attributes = @params.attributes.symbolize_keys
        attributes[:code] = attributes[:code].to_s.strip.downcase if attributes.key?(:code)
        %i[name_en name_ur].each { |field| attributes[field] = attributes[field].to_s.strip if attributes.key?(field) }
        attributes
      end

      def record_audit!
        AuditEvent.create!(audit_attributes)
      end

      def audit_attributes
        {
          actor: @params.actor,
          entity_type: 'ReferenceData',
          entity_id: @record.id,
          action_code: "reference_data_#{@params.action}",
          metadata: audit_metadata,
          request_id: @params.request_id,
          occurred_at: Time.current
        }
      end

      def audit_metadata
        {
          reference_type: @params.record_class.name.underscore,
          code: @record.code,
          changed_fields: audit_changed_fields
        }
      end

      def audit_changed_fields
        return ['active'] if @params.action == :retire

        normalized_attributes.keys.map(&:to_s)
      end
    end
  end
end
