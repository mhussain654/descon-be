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
          token = SecureRandom.urlsafe_base64(32)
          batch = persist_batch!(token:, rows: plan_rows(rows:, result:), result:)
          create_audit_event!(batch:)
          response(result:, batch:, token:)
        end

        private

        def persist_batch!(token:, rows:, result:)
          CandidateImportBatch.create!(batch_attributes(token:, rows:, result:))
        end

        def batch_attributes(token:, rows:, result:)
          summary = result.summary
          { actor: @actor, token_digest: digest(token), source_filename: File.basename(@file.original_filename.to_s),
            file_fingerprint: file_fingerprint, template_version: Template::VERSION, request_id: @request_id,
            status: 'queued',
            preflight_payload: { rows: }.to_json, total_rows: summary.fetch(:total_rows),
            accepted_rows: result.persistable_rows.size,
            rejected_rows: summary.fetch(:failed_rows) + summary.fetch(:skipped_rows),
            warning_count: 0, expires_at: Time.current + EXPIRY }
        end

        def response(result:, batch:, token:)
          result.to_h.merge(import_id: batch.public_id, preflight_token: token, expires_at: batch.expires_at.iso8601,
                            accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows, warning_count: 0)
        end

        def plan_rows(rows:, result:)
          builder = RowBuilder.new(actor: @actor)
          tracker = DuplicateTracker.new
          rows.each_with_index.filter_map do |row, index|
            process_row(row:, row_number: index + 2, builder:, tracker:, result:)
          end
        end

        def process_row(row:, row_number:, builder:, tracker:, result:)
          attributes = CsvFileParser::SUPPORTED_HEADERS.index_with { |header| row[header].to_s.strip }
          plan = builder.call(row:, row_number:)
          error = row_error(plan:, tracker:)
          return result.record_failed(row_number:, errors: [error]) if error

          result.schedule(plan)
          attributes.merge('template_version' => Template::VERSION, 'row_number' => row_number)
        end

        def row_error(plan:, tracker:)
          return { field: 'row', code: 'blank_row' } if plan.blank?
          return plan.errors.first if plan.invalid?

          tracker.register(plan) || database_duplicate(plan)
        end

        def database_duplicate(plan)
          return { field: 'cnic', code: 'duplicate_candidate' } if Candidate.exists?(cnic: plan.cnic)

          passport_duplicate(plan) || mobile_duplicate(plan) || reference_duplicate(plan)
        end

        def passport_duplicate(plan)
          return if plan.passport_number.blank?
          return unless Candidate.exists?(passport_number: plan.passport_number)

          { field: 'passport_number', code: 'duplicate_passport' }
        end

        def mobile_duplicate(plan)
          return unless Candidate.exists?(mobile_number: plan.mobile_number)

          { field: 'mobile_number', code: 'duplicate_mobile_number' }
        end

        def reference_duplicate(plan)
          return unless CandidateAssignment.exists?(reference_number: plan.reference_number)

          { field: 'reference_number', code: 'duplicate_reference_number' }
        end

        def validate_template_version!(rows)
          return if rows.all? { |row| row['template_version'].to_s.strip == Template::VERSION }

          raise ValidationError.new(field: 'candidate_import.template_version',
                                    message: I18n.t('api.candidate_imports.errors.unsupported_template_version'))
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
                             action_code: 'candidate_import_preflighted', request_id: @request_id,
                             occurred_at: Time.current,
                             metadata: { import_public_id: batch.public_id, template_version: batch.template_version,
                                         file_fingerprint: batch.file_fingerprint, total_rows: batch.total_rows,
                                         accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows })
        end
      end
    end
  end
end
