# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class BatchExecutionService < ApplicationService
        def initialize(import_id:, request_id:)
          @import_id = import_id
          @request_id = request_id
        end

        def call
          batch = claim_batch
          return if batch.blank?

          execute_rows(batch)
          complete!(batch)
        end

        def self.record_failure(import_id:, request_id:)
          CandidateImportBatch.transaction do
            batch = CandidateImportBatch.lock.find_by!(public_id: import_id)
            return unless batch.processing?

            batch.update!(status: 'failed', failed_at: Time.current, error_code: 'processing_failed')
            create_audit_event(batch:, request_id:, action_code: 'candidate_import_failed')
          end
        end

        private

        def claim_batch
          CandidateImportBatch.transaction do
            batch = CandidateImportBatch.lock.find_by!(public_id: @import_id)
            return invalidate!(batch) if batch.expired?
            return if batch.processing? || batch.committed? || batch.invalidated?
            return unless batch.queued? || batch.failed?

            batch.update!(status: 'processing', error_code: nil, failed_at: nil)
            batch
          end
        end

        def invalidate!(batch)
          batch.update!(status: 'invalidated', preflight_payload: nil) unless batch.invalidated?
          nil
        end

        def execute_rows(batch)
          rows_by_number = batch.rows.index_by { |row| row.fetch('row_number') }
          batch.row_results.where(status: 'accepted').find_each do |row_result|
            persist_row(batch:, row_result:, row: rows_by_number.fetch(row_result.row_number))
          end
        end

        def persist_row(batch:, row_result:, row:)
          result = Result.new(total_rows: 1)
          plan = RowBuilder.new(actor: batch.actor).call(row: row.except('row_number', 'template_version'),
                                                         row_number: row_result.row_number)
          return update_row_result!(row_result, status: 'rejected', error: plan.errors.first) if plan.invalid?

          RowPersister.new.call(row_plan: plan, result:)
          update_from_result!(row_result, result)
        end

        def update_from_result!(row_result, result)
          outcome = result.to_h
          if outcome[:successful_rows].positive?
            return row_result.update!(status: 'committed', error_field: nil,
                                      error_code: nil)
          end

          error = outcome.fetch(:errors).first
          update_row_result!(row_result, status: 'skipped',
                                         error: { field: error.fetch(:field), code: error.fetch(:code) })
        end

        def update_row_result!(row_result, status:, error:)
          row_result.update!(status:, error_field: error.fetch(:field), error_code: error.fetch(:code))
        end

        def complete!(batch)
          CandidateImportBatch.transaction do
            batch.lock!
            return unless batch.processing?

            complete_batch!(batch)
          end
        end

        def complete_batch!(batch)
          counts = batch.row_results.group(:status).count
          batch.update!(completion_attributes(counts))
          self.class.send(
            :create_audit_event,
            batch:,
            request_id: @request_id,
            action_code: 'candidate_import_committed'
          )
        end

        def completion_attributes(counts)
          rejected_rows = counts.fetch('rejected', 0)
          skipped_rows = counts.fetch('skipped', 0)
          committed_rows = counts.fetch('committed', 0)
          {
            status: rejected_rows.zero? && skipped_rows.zero? ? 'completed' : 'partial',
            processed_at: Time.current, committed_at: Time.current, imported_rows: committed_rows,
            committed_rows:, rejected_rows:, skipped_rows:
          }
        end

        def self.create_audit_event(batch:, request_id:, action_code:)
          AuditEvent.create!(actor: batch.actor, entity_type: 'CandidateImportBatch', entity_id: batch.id,
                             action_code:, request_id:, occurred_at: Time.current,
                             metadata: { import_public_id: batch.public_id, total_rows: batch.total_rows,
                                         committed_rows: batch.committed_rows, rejected_rows: batch.rejected_rows,
                                         skipped_rows: batch.skipped_rows })
        end
        private_class_method :create_audit_event
      end
    end
  end
end
