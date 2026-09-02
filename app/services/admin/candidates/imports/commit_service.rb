# frozen_string_literal: true

require 'digest'

module Admin
  module Candidates
    module Imports
      class CommitService < ApplicationService
        def initialize(actor:, token:, request_id:, idempotency_key: nil)
          @actor = actor
          @token = token.to_s
          @request_id = request_id
          @idempotency_key = idempotency_key
        end

        def call
          CandidateImportBatch.transaction do
            Database::AdvisoryTransactionLock.call(scope: 'candidate-import-commit', key: Digest::SHA256.hexdigest(@token))
            batch = CandidateImportBatch.lock.find_by(token_digest: Digest::SHA256.hexdigest(@token))
            validate_batch!(batch)
            return committed_payload(batch) if batch.committed?

            result = Result.new(total_rows: batch.total_rows)
            batch.rows.each { |row| persist_row(row:, result:) }
            finalize!(batch:, result:)
            committed_payload(batch, result:)
          end
        end

        private

        def validate_batch!(batch)
          if batch.blank? || batch.actor_id != @actor.id
            raise ValidationError.new(field: 'candidate_import.preflight_token',
                                      message: I18n.t('api.candidate_imports.errors.invalid_preflight_token'))
          end
          return unless batch.expired? || batch.status == 'invalidated'

          raise ValidationError.new(field: 'candidate_import.preflight_token',
                                    message: I18n.t('api.candidate_imports.errors.expired_preflight_token'))
        end

        def persist_row(row:, result:)
          attributes = row.except('row_number', 'template_version')
          plan = RowBuilder.new(actor: @actor).call(row: attributes, row_number: row.fetch('row_number'))
          if plan.invalid?
            result.record_failed(row_number: plan.row_number, errors: plan.errors)
          else
            RowPersister.new.call(row_plan: plan, result:)
          end
        end

        def finalize!(batch:, result:)
          batch.transaction do
            batch.update!(commit_attributes(batch:, result:))
            create_commit_audit!(batch:)
          end
        end

        def commit_attributes(batch:, result:)
          summary = result.summary
          {
            status: 'committed', committed_at: Time.current,
            imported_rows: summary.fetch(:successful_rows),
            rejected_rows: batch.rejected_rows + summary.fetch(:failed_rows) + summary.fetch(:skipped_rows)
          }
        end

        def create_commit_audit!(batch:)
          AuditEvent.create!(
            actor: @actor, entity_type: 'CandidateImportBatch', entity_id: batch.id,
            action_code: 'candidate_import_committed', request_id: @request_id,
            occurred_at: Time.current, metadata: commit_audit_metadata(batch:)
          )
        end

        def commit_audit_metadata(batch:)
          {
            import_public_id: batch.public_id, template_version: batch.template_version,
            file_fingerprint: batch.file_fingerprint, total_rows: batch.total_rows,
            accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows,
            imported_rows: batch.imported_rows, idempotency_key_present: @idempotency_key.present?
          }
        end

        def committed_payload(batch, result: nil)
          summary = if result
                      result.to_h
                    else
                      replay_summary(batch)
                    end
          summary.merge(import_id: batch.public_id, status: batch.status, total_rows: batch.total_rows,
                        imported_rows: batch.imported_rows, rejected_rows: batch.rejected_rows,
                        warning_count: batch.warning_count)
        end

        def replay_summary(batch)
          { successful_rows: batch.imported_rows,
            failed_rows: batch.rejected_rows - batch.total_rows + batch.accepted_rows,
            skipped_rows: 0, errors: [] }
        end
      end
    end
  end
end
