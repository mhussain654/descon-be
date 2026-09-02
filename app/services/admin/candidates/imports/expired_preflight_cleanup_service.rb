# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class ExpiredPreflightCleanupService < ApplicationService
        def call
          CandidateImportBatch.where('expires_at <= ?', Time.current).where.not(preflight_payload: nil).find_each do |batch|
            CandidateImportBatch.transaction do
              batch.lock!
              next if batch.preflight_payload.blank? || !batch.expired?

              batch.update!(status: 'invalidated', preflight_payload: nil) unless batch.processing? || batch.committed?
              batch.update!(preflight_payload: nil) if batch.preflight_payload.present?
            end
          end
        end
      end
    end
  end
end
