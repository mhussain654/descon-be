# frozen_string_literal: true

module Admin
  module DocumentRequirements
    # Adds a document to the common checklist or a country's, or edits a
    # checklist row (developer-only, `manage_reference_data`). Only the
    # candidate-facing settings change here: requirement level, on/off, file
    # count and types, and instructions. Scope (country, project, craft,
    # drivers) and upload labels stay as seeded.
    class MutationService < ApplicationService
      EDITABLE_FIELDS = %i[requirement_level active maximum_files accepted_content_types instructions_en
                           instructions_ur].freeze

      def initialize(actor:, attributes:, requirement: nil, expected_updated_at: nil, request_id: nil)
        @actor = actor
        @requirement = requirement
        @attributes = attributes.to_h.symbolize_keys
        @expected_updated_at = expected_updated_at
        @request_id = request_id
      end

      def call
        validate_actor!
        DocumentRequirement.transaction do
          record = @requirement ? update! : create!
          record_audit!(record)
          record
        end
      rescue ActiveRecord::RecordNotUnique
        invalid!('document_requirement.document_type_code', 'document_requirement_exists')
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('manage_reference_data')
      end

      def create!
        document_type = DocumentType.find_by(code: @attributes[:document_type_code].to_s, active: true)
        invalid!('document_requirement.document_type_code', 'unknown_document_type') unless document_type
        country = @attributes[:country_code].presence && Country.find_by!(code: @attributes[:country_code].to_s)
        if DocumentRequirement.exists?(document_type:, country:, project_id: nil, craft_id: nil)
          invalid!('document_requirement.document_type_code', 'document_requirement_exists')
        end

        DocumentRequirement.create!(editable_attributes.merge(document_type:, country:,
                                                              display_position: next_position))
      end

      def update!
        @requirement.lock!
        validate_staleness!
        @requirement.update!(editable_attributes)
        @requirement
      end

      def validate_staleness!
        return if @expected_updated_at.blank?

        expected = Time.iso8601(@expected_updated_at.to_s)
        raise StaleReferenceDataError unless expected.to_i == @requirement.updated_at.to_i
      rescue ArgumentError
        invalid!('expected_updated_at', 'validation_failed')
      end

      def editable_attributes
        @attributes.slice(*EDITABLE_FIELDS).tap do |attributes|
          %i[instructions_en instructions_ur].each do |field|
            attributes[field] = attributes[field].to_s.strip.presence if attributes.key?(field)
          end
          if attributes.key?(:accepted_content_types)
            attributes[:accepted_content_types] =
              Array(attributes[:accepted_content_types]).uniq
          end
        end
      end

      def next_position
        DocumentRequirement.maximum(:display_position).to_i + 10
      end

      def record_audit!(record)
        AuditEvent.create!(
          actor: @actor, entity_type: 'DocumentRequirement', entity_id: record.id,
          action_code: @requirement ? 'document_requirement_update' : 'document_requirement_create',
          metadata: { document_type: record.document_type.code, country: record.country&.code,
                      changed_fields: editable_attributes.keys.map(&:to_s) },
          request_id: @request_id, occurred_at: Time.current
        )
      end

      def invalid!(field, key)
        raise ValidationError.new(field:, message: I18n.t("api.errors.#{key}"))
      end
    end
  end
end
