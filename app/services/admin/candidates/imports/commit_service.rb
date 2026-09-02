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
          batch, enqueue = claim_batch
          ::Admin::CandidateImports::ExecuteJob.perform_later(batch.public_id, @request_id) if enqueue
          payload(batch)
        end

        private

        def claim_batch
          CandidateImportBatch.transaction do
            Database::AdvisoryTransactionLock.call(scope: 'candidate-import-commit', key: Digest::SHA256.hexdigest(@token))
            batch = CandidateImportBatch.lock.find_by(token_digest: Digest::SHA256.hexdigest(@token))
            validate_batch!(batch)
            return [batch, false] if batch.committed? || batch.processing? || batch.enqueued_at.present?

            batch.update!(status: 'queued', enqueued_at: Time.current, error_code: nil, failed_at: nil)
            [batch, true]
          end
        end

        def validate_batch!(batch)
          if batch.blank? || batch.actor_id != @actor.id
            raise ValidationError.new(field: 'candidate_import.preflight_token',
                                      message: I18n.t('api.candidate_imports.errors.invalid_preflight_token'))
          end
          return unless batch.expired? || batch.invalidated?

          raise ValidationError.new(field: 'candidate_import.preflight_token',
                                    message: I18n.t('api.candidate_imports.errors.expired_preflight_token'))
        end

        def payload(batch)
          {
            import_id: batch.public_id, status: batch.status, total_rows: batch.total_rows,
            accepted_rows: batch.accepted_rows, rejected_rows: batch.rejected_rows,
            skipped_rows: batch.skipped_rows, committed_rows: batch.committed_rows,
            idempotency_key_present: @idempotency_key.present?
          }
        end
      end
    end
  end
end
