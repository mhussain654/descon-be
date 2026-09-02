# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class ExpiredPreflightCleanupService < ApplicationService
        def call
          expired_batches.find_each do |batch|
            cleanup_batch(batch)
          end
        end

        private

        def expired_batches
          CandidateImportBatch.where(expires_at: ..Time.current).where.not(preflight_payload: nil)
        end

        def cleanup_batch(batch)
          CandidateImportBatch.transaction do
            batch.lock!
            next if batch.preflight_payload.blank? || !batch.expired? || batch.processing?

            batch.update!(cleanup_attributes(batch))
          end
        end

        def cleanup_attributes(batch)
          return { preflight_payload: nil } if batch.committed?

          { status: 'invalidated', invalidated_at: Time.current, preflight_payload: nil }
        end
      end
    end
  end
end
