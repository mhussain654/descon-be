# frozen_string_literal: true

require 'digest'

module Admin
  module Candidates
    module Imports
      class PreflightService < ApplicationService
        EXPIRY = 30.minutes

        def initialize(actor:, file:, request_id:)
          @actor = actor
          @file = file
          @request_id = request_id
        end

        def call
          rows = CsvFileParser.call(file: @file)
          validate_template_version!(rows)
          result = Result.new(total_rows: rows.size)
          normalized_rows = plan_rows(rows:, result:)
          token = SecureRandom.urlsafe_base64(32)
          batch = CandidateImportBatch.create!(
            actor: @actor,
            token_digest: digest(token),
            source_filename: File.basename(@file.original_filename.to_s),
            file_fingerprint: file_fingerprint,
            template_version: Template::VERSION,
            request_id: @request_id,
            preflight_payload: { rows: normalized_rows }.to_json,
            total_rows: result.summary.fetch(:total_rows),
            accepted_rows: result.persistable_rows.size,
            rejected_rows: result.summary.fetch(:failed_rows) + result.summary.fetch(:skipped_rows),
            warning_count: 0,
            expires_at: Time.current + EXPIRY
          )
          create_audit_event!(batch:)

          result.to_h.merge(import_id: batch.public_id, preflight_token: token, expires_at: batch.expires_at.iso8601,
                            accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows, warning_count: 0)
        end

        private

        def plan_rows(rows:, result:)
          builder = RowBuilder.new(actor: @actor)
          tracker = DuplicateTracker.new
          rows.each_with_index.filter_map do |row, index|
            attributes = CsvFileParser::SUPPORTED_HEADERS.index_with { |header| row[header].to_s.strip }
            plan = builder.call(row:, row_number: index + 2)
            if plan.blank?
              result.record_failed(row_number: index + 2, errors: [{ field: 'row', code: 'blank_row' }])
            elsif plan.invalid?
              result.record_failed(row_number: plan.row_number, errors: plan.errors)
            elsif (duplicate_error = tracker.register(plan))
              result.record_failed(row_number: plan.row_number, errors: [duplicate_error])
            elsif (duplicate_error = database_duplicate(plan))
              result.record_failed(row_number: plan.row_number, errors: [duplicate_error])
            else
              result.schedule(plan)
              attributes.merge('template_version' => Template::VERSION, 'row_number' => plan.row_number)
            end
          end
        end

        def database_duplicate(plan)
          return { field: 'cnic', code: 'duplicate_candidate' } if Candidate.exists?(cnic: plan.cnic)
          return { field: 'passport_number', code: 'duplicate_passport' } if plan.passport_number.present? && Candidate.exists?(passport_number: plan.passport_number)
          return { field: 'mobile_number', code: 'duplicate_mobile_number' } if Candidate.exists?(mobile_number: plan.mobile_number)
          return { field: 'reference_number', code: 'duplicate_reference_number' } if CandidateAssignment.exists?(reference_number: plan.reference_number)

          nil
        end

        def validate_template_version!(rows)
          return if rows.all? { |row| row['template_version'].to_s.strip == Template::VERSION }

          raise ValidationError.new(field: 'candidate_import.template_version', message: I18n.t('api.candidate_imports.errors.unsupported_template_version'))
        end

        def file_fingerprint
          contents = @file.read.to_s
          Digest::SHA256.hexdigest(contents)
        ensure
          @file.rewind if @file.respond_to?(:rewind)
        end

        def digest(token) = Digest::SHA256.hexdigest(token)

        def create_audit_event!(batch:)
          AuditEvent.create!(actor: @actor, entity_type: 'CandidateImportBatch', entity_id: batch.id,
                             action_code: 'candidate_import_preflighted', request_id: @request_id, occurred_at: Time.current,
                             metadata: { import_public_id: batch.public_id, template_version: batch.template_version,
                                         file_fingerprint: batch.file_fingerprint, total_rows: batch.total_rows,
                                         accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows })
        end
      end
    end
  end
end
