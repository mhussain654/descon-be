# frozen_string_literal: true

require 'csv'

module Admin
  module Candidates
    class ImportService < ApplicationService
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_IMPORT_MAX_BYTES', 2.megabytes).to_i
      MAX_ROWS = ENV.fetch('CANDIDATE_IMPORT_MAX_ROWS', 1000).to_i
      REQUIRED_HEADERS = %w[
        full_name
        cnic
        mobile_number
        reference_number
        preferred_locale
        candidate_status
        workflow_stage_code
        country_code
        project_code
        craft_code
        active
      ].freeze
      ALLOWED_CONTENT_TYPES = %w[text/csv application/csv text/plain application/vnd.ms-excel].freeze
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

      def initialize(actor:, file:, request_id:)
        @actor = actor
        @file = file
        @request_id = request_id
        @errors = []
        @successful_rows = 0
        @failed_rows = 0
        @skipped_rows = 0
        @seen_cnics = Set.new
        @seen_reference_numbers = Set.new
      end

      def call
        validate_file!
        rows = parsed_rows

        raise_no_rows_error! if rows.empty?
        raise_too_many_rows_error! if rows.size > MAX_ROWS

        rows.each_with_index do |row, index|
          process_row(row, row_number: index + 2)
        end

        audit_import!(total_rows: rows.size)

        {
          successful_rows: @successful_rows,
          failed_rows: @failed_rows,
          skipped_rows: @skipped_rows,
          total_rows: rows.size,
          errors: @errors
        }
      end

      private

      def validate_file!
        raise_file_missing_error! if @file.blank?
        raise_invalid_file_type_error! unless valid_file_type?
        raise_file_too_large_error! if @file.size.to_i > MAX_FILE_BYTES
      end

      def valid_file_type?
        extension = File.extname(@file.original_filename.to_s).downcase
        content_type = @file.content_type.to_s

        extension == '.csv' && (content_type.blank? || ALLOWED_CONTENT_TYPES.include?(content_type))
      end

      def parsed_rows
        csv = CSV.parse(@file.read.to_s, headers: true, header_converters: ->(header) { normalize_header(header) })
        headers = csv.headers.compact
        missing_headers = REQUIRED_HEADERS - headers
        raise_missing_headers_error!(missing_headers) if missing_headers.any?

        csv
      rescue CSV::MalformedCSVError
        raise_invalid_csv_error!
      ensure
        @file.rewind if @file.respond_to?(:rewind)
      end

      def normalize_header(header)
        header.to_s.strip.downcase
      end

      def process_row(row, row_number:)
        attributes = normalized_row_attributes(row)
        return register_failed_row(row_number:, errors: [{ field: 'row', code: 'blank_row' }]) if blank_row?(attributes)

        duplicate_in_file_error = duplicate_in_file_error(attributes)
        return register_failed_row(row_number:, errors: [duplicate_in_file_error]) if duplicate_in_file_error

        row_errors = []
        candidate_attributes = build_candidate_attributes(attributes, row_errors:)
        assignment_attributes = build_assignment_attributes(attributes, row_errors:)
        return register_failed_row(row_number:, errors: row_errors) if row_errors.any?

        persist_row(candidate_attributes:, assignment_attributes:, row_number:)
      end

      def normalized_row_attributes(row)
        REQUIRED_HEADERS.index_with { |header| row[header].to_s.strip }
      end

      def blank_row?(attributes)
        attributes.values.all?(&:blank?)
      end

      def duplicate_in_file_error(attributes)
        cnic = ::Candidates::CnicNormalizer.call(attributes.fetch('cnic'))
        reference_number = attributes.fetch('reference_number').upcase

        return { field: 'cnic', code: 'duplicate_cnic_in_file' } if @seen_cnics.include?(cnic)

        if @seen_reference_numbers.include?(reference_number)
          return { field: 'reference_number', code: 'duplicate_reference_number_in_file' }
        end

        @seen_cnics << cnic
        @seen_reference_numbers << reference_number
        nil
      end

      def build_candidate_attributes(attributes, row_errors:)
        {
          full_name: presence_or_error(attributes, 'full_name', row_errors:),
          cnic: validated_cnic(attributes.fetch('cnic'), row_errors:),
          mobile_number: validated_mobile_number(attributes.fetch('mobile_number'), row_errors:),
          preferred_locale: validated_locale(attributes.fetch('preferred_locale'), row_errors:),
          status_code: validated_status_code(attributes.fetch('candidate_status'), row_errors:),
          active: validated_active(attributes.fetch('active'), row_errors:),
          source_code: 'csv_import',
          created_by: @actor
        }
      end

      def build_assignment_attributes(attributes, row_errors:)
        {
          reference_number: validated_reference_number(
            attributes.fetch('reference_number'),
            row_errors:
          ),
          current_workflow_stage: referenced_record(
            WorkflowStage.where(active: true),
            attributes.fetch('workflow_stage_code'),
            field: 'workflow_stage_code',
            row_errors:
          ),
          country: referenced_record(
            Country.where(active: true),
            attributes.fetch('country_code'),
            field: 'country_code',
            row_errors:
          ),
          project: referenced_record(
            Project.where(active: true),
            attributes.fetch('project_code'),
            field: 'project_code',
            row_errors:
          ),
          craft: referenced_record(
            Craft.where(active: true),
            attributes.fetch('craft_code'),
            field: 'craft_code',
            row_errors:
          ),
          created_by: @actor
        }
      end

      def presence_or_error(attributes, field_name, row_errors:)
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

      def validated_reference_number(raw_value, row_errors:)
        value = raw_value.to_s.strip.upcase
        return value if value.present?

        row_errors << { field: 'reference_number', code: 'missing_value' }
        nil
      end

      def referenced_record(scope, raw_code, field:, row_errors:)
        code = raw_code.to_s.strip.downcase
        record = scope.find_by(code:)
        return record if record.present?

        row_errors << { field:, code: "unknown_#{field}" }
        nil
      end

      def persist_row(candidate_attributes:, assignment_attributes:, row_number:)
        if duplicate_candidate?(candidate_attributes.fetch(:cnic))
          return register_skipped_row(row_number:, field: 'cnic', code: 'duplicate_candidate')
        end

        if duplicate_reference_number?(assignment_attributes.fetch(:reference_number))
          return register_skipped_row(row_number:, field: 'reference_number', code: 'duplicate_reference_number')
        end

        ActiveRecord::Base.transaction do
          candidate = ::Candidate.create!(candidate_attributes)
          candidate.candidate_assignments.create!(assignment_attributes)
        end

        @successful_rows += 1
      rescue ActiveRecord::RecordInvalid
        register_failed_row(row_number:, errors: [{ field: 'row', code: 'validation_failed' }])
      rescue ActiveRecord::RecordNotUnique
        register_skipped_row(row_number:, field: 'row', code: 'duplicate_row')
      end

      def duplicate_candidate?(cnic)
        ::Candidate.exists?(cnic:)
      end

      def duplicate_reference_number?(reference_number)
        ::CandidateAssignment.exists?(reference_number:)
      end

      def register_failed_row(row_number:, errors:)
        @failed_rows += 1
        errors.each do |error|
          @errors << localized_row_error(row_number:, field: error.fetch(:field), code: error.fetch(:code))
        end
        nil
      end

      def register_skipped_row(row_number:, field:, code:)
        @skipped_rows += 1
        @errors << localized_row_error(row_number:, field:, code:)
        nil
      end

      def localized_row_error(row_number:, field:, code:)
        {
          row: row_number,
          field:,
          code:,
          message: I18n.t("api.candidate_imports.row_errors.#{code}")
        }
      end

      def raise_no_rows_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.no_rows')
        )
      end

      def raise_too_many_rows_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.too_many_rows')
        )
      end

      def raise_file_missing_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.file_missing')
        )
      end

      def raise_invalid_file_type_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.invalid_file_type')
        )
      end

      def raise_file_too_large_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.file_too_large')
        )
      end

      def raise_missing_headers_error!(missing_headers)
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.missing_headers', headers: missing_headers.join(', '))
        )
      end

      def raise_invalid_csv_error!
        raise ValidationError.new(
          field: 'candidate_import.file',
          message: I18n.t('api.candidate_imports.errors.invalid_csv')
        )
      end

      def audit_import!(total_rows:)
        AuditEvent.create!(
          actor: @actor,
          entity_type: 'User',
          entity_id: @actor.id,
          action_code: 'candidate_import_completed',
          request_id: @request_id,
          metadata: {
            successful_rows: @successful_rows,
            failed_rows: @failed_rows,
            skipped_rows: @skipped_rows,
            total_rows:
          },
          occurred_at: Time.current
        )
      end
    end
  end
end
