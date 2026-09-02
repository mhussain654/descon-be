# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class RetryService < ApplicationService
        def initialize(actor:, batch:, request_id:)
          @actor = actor
          @batch = batch
          @request_id = request_id
        end

        def call
          CandidateImportBatch.transaction do
            batch = CandidateImportBatch.lock.find(@batch.id)
            validate_retry!(batch)
            batch.update!(status: 'queued', enqueued_at: Time.current, error_code: nil, failed_at: nil)
            create_audit_event!(batch)
            batch
          end
        end

        private

        def validate_retry!(batch)
          return if batch.actor_id == @actor.id && batch.failed? && !batch.expired?

          raise ValidationError.new(
            field: 'candidate_import.status',
            message: I18n.t('api.candidate_imports.errors.retry_not_allowed')
          )
        end

        def create_audit_event!(batch)
          AuditEvent.create!(
            actor: @actor, entity_type: 'CandidateImportBatch', entity_id: batch.id,
            action_code: 'candidate_import_retried', request_id: @request_id, occurred_at: Time.current,
            metadata: { import_public_id: batch.public_id }
          )
        end
      end
    end
  end
end
