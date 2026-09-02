# frozen_string_literal: true

require 'csv'

module Admin
  module Candidates
    module Imports
      class CsvFileParser < ApplicationService
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
        OPTIONAL_HEADERS = %w[
          passport_number
          next_of_kin_name
          next_of_kin_relationship
          next_of_kin_mobile_number
          next_of_kin_cnic
        ].freeze
        VERSION_HEADER = 'template_version'
        SUPPORTED_HEADERS = (REQUIRED_HEADERS + OPTIONAL_HEADERS + [VERSION_HEADER]).freeze
        ALLOWED_CONTENT_TYPES = %w[
          text/csv
          application/csv
          text/plain
          application/vnd.ms-excel
        ].freeze

        def initialize(file:)
          @file = file
        end

        def call
          validate_file!
          rows = parse_rows
          raise_error!('no_rows') if rows.empty?
          raise_error!('too_many_rows') if rows.size > MAX_ROWS

          rows
        end

        private

        def validate_file!
          raise_error!('file_missing') if @file.blank?
          raise_error!('invalid_file_type') unless valid_file_type?
          raise_error!('file_too_large') if @file.size.to_i > MAX_FILE_BYTES
        end

        def valid_file_type?
          extension = File.extname(@file.original_filename.to_s).downcase
          content_type = @file.content_type.to_s

          extension == '.csv' && (content_type.blank? || ALLOWED_CONTENT_TYPES.include?(content_type))
        end

        def parse_rows
          csv = parse_csv!
          validate_headers!(csv.headers.compact)
          csv
        rescue CSV::MalformedCSVError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          raise_error!('invalid_csv')
        ensure
          @file.rewind if @file.respond_to?(:rewind)
        end

        def parse_csv!
          content = @file.read.to_s
          raise_error!('invalid_encoding') unless content.force_encoding(Encoding::UTF_8).valid_encoding?

          CSV.parse(content, headers: true, header_converters: [method(:normalize_header).to_proc])
        end

        def validate_headers!(headers)
          missing_headers = REQUIRED_HEADERS - headers
          raise_missing_headers_error!(missing_headers) if missing_headers.any?

          unsupported_headers = headers - SUPPORTED_HEADERS
          raise_unsupported_headers_error!(unsupported_headers) if unsupported_headers.any?
        end

        def normalize_header(header)
          header.to_s.strip.downcase
        end

        def raise_missing_headers_error!(missing_headers)
          raise ValidationError.new(
            field: 'candidate_import.file',
            message: I18n.t(
              'api.candidate_imports.errors.missing_headers',
              headers: missing_headers.join(', ')
            )
          )
        end

        def raise_unsupported_headers_error!(headers)
          raise ValidationError.new(
            field: 'candidate_import.file',
            message: I18n.t('api.candidate_imports.errors.unsupported_headers', headers: headers.join(', '))
          )
        end

        def raise_error!(translation_key)
          raise ValidationError.new(
            field: 'candidate_import.file',
            message: I18n.t("api.candidate_imports.errors.#{translation_key}")
          )
        end
      end
    end
  end
end
