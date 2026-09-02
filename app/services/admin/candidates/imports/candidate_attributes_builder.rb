# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class CandidateAttributesBuilder
        BOOLEAN_VALUES = {
          'true' => true,
          'false' => false,
          '1' => true,
          '0' => false,
          'yes' => true,
          'no' => false,
          'active' => true,
          'inactive' => false
        }.freeze

        def initialize(actor:)
          @actor = actor
        end

        def call(attributes:, row_errors:)
          required_attributes(attributes,
                              row_errors:).merge(optional_attributes(attributes)).tap do |candidate_attributes|
            validate_next_of_kin(candidate_attributes, row_errors:)
          end
        end

        private

        def required_attributes(attributes, row_errors:)
          {
            full_name: required_value(attributes, 'full_name', row_errors:),
            cnic: validated_cnic(attributes.fetch('cnic'), row_errors:),
            mobile_number: validated_mobile_number(attributes.fetch('mobile_number'), row_errors:),
            preferred_locale: validated_locale(attributes.fetch('preferred_locale'), row_errors:),
            status_code: validated_status_code(attributes.fetch('candidate_status'), row_errors:),
            active: validated_active(attributes.fetch('active'), row_errors:),
            source_code: 'csv_import',
            created_by: @actor
          }
        end

        def optional_attributes(attributes)
          %w[passport_number next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic]
            .index_with { |field| optional_value(attributes, field) }
            .transform_keys(&:to_sym)
        end

        def optional_value(attributes, field_name)
          attributes[field_name].to_s.strip.presence
        end

        def validate_next_of_kin(candidate_attributes, row_errors:)
          fields = %i[next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic]
          return if fields.all? { |field| candidate_attributes[field].blank? }
          return if fields.all? { |field| candidate_attributes[field].present? }

          fields.each do |field|
            row_errors << { field: field.to_s, code: 'incomplete_next_of_kin' } if candidate_attributes[field].blank?
          end
        end

        def required_value(attributes, field_name, row_errors:)
          value = attributes.fetch(field_name)
          return value if value.present?

          row_errors << { field: field_name, code: 'missing_value' }
          nil
        end

        def validated_cnic(raw_value, row_errors:)
          value = ::Candidates::CnicNormalizer.call(raw_value)
          return value if value.match?(::Candidate::CNIC_FORMAT)

          row_errors << { field: 'cnic', code: 'invalid_cnic' }
          nil
        end

        def validated_mobile_number(raw_value, row_errors:)
          digits = raw_value.gsub(/\D/, '')
          normalized = raw_value.start_with?('+') ? "+#{digits}" : digits
          return normalized if normalized.match?(::Candidate::MOBILE_NUMBER_FORMAT)

          row_errors << { field: 'mobile_number', code: 'invalid_mobile_number' }
          nil
        end

        def validated_locale(raw_value, row_errors:)
          locale = raw_value.downcase
          return locale if ::Candidate::PREFERRED_LOCALES.include?(locale)

          row_errors << { field: 'preferred_locale', code: 'invalid_preferred_locale' }
          nil
        end

        def validated_status_code(raw_value, row_errors:)
          value = raw_value.to_s.strip.downcase
          return value if value.match?(::Candidate::STATUS_CODE_FORMAT)

          row_errors << { field: 'candidate_status', code: 'invalid_candidate_status' }
          nil
        end

        def validated_active(raw_value, row_errors:)
          normalized_value = raw_value.to_s.strip.downcase
          return BOOLEAN_VALUES.fetch(normalized_value) if BOOLEAN_VALUES.key?(normalized_value)

          row_errors << { field: 'active', code: 'invalid_active_state' }
          nil
        end
      end
    end
  end
end
