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
        raise ForbiddenError unless @params.actor.permission?('manage_reference_data')
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
        when :restore then @record.update!(active: true)
        when :destroy then destroy_unused!
        else raise ArgumentError, "unsupported reference-data action: #{@params.action}"
        end
      end

      # Deleting is only for a value nothing points at (e.g. a typo just
      # added); a value in use is retired instead, so candidates keep theirs.
      def destroy_unused!
        raise ReferenceDataInUseError if in_use?

        @record.destroy!
      end

      # Any row in any table referencing this value through a foreign key.
      def in_use?
        connection = @params.record_class.connection
        connection.tables.any? do |table|
          connection.foreign_keys(table).any? do |key|
            key.to_table == @params.record_class.table_name && referencing_rows?(table, key.column)
          end
        end
      end

      def referencing_rows?(table, column)
        Class.new(ApplicationRecord) { self.table_name = table }.exists?(column => @record.id)
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
        return ['active'] if %i[retire restore].include?(@params.action)
        return [] if @params.action == :destroy

        normalized_attributes.keys.map(&:to_s)
      end
    end
  end
end
