# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Re-runs a previously failed (or partially failed) bulk candidate
      # import batch.
      class CandidateImportRetriesController < ProtectedStaffController
        # Marks the import batch for retry and enqueues a background job to
        # re-process it; deduplicated so a repeated request doesn't
        # re-enqueue the same batch twice.
        def create
          authorize import_batch, :retry?, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.retry', subject: current_user) do
            retry_payload
          end
        end

        private

        # Loads the import batch named in the route, scoped to what the
        # current staff member is authorized to view/manage.
        def import_batch
          policy_scope(::CandidateImportBatch, policy_scope_class: ::Admin::CandidateImportPolicy::Scope)
            .find_by!(public_id: params.expect(:candidate_import_id))
        end

        # Transitions the batch to retry state, enqueues the reprocessing
        # job, and serializes the accepted batch for the response.
        def retry_payload
          batch = retry_batch
          enqueue(batch)
          set_private_state_headers(updated_at: batch.updated_at, etag_key: batch.public_id)
          success_payload(data: ::Admin::CandidateImports::BatchSerializer.new(batch).as_json, status: :accepted)
        end

        # Delegates the retry transition to the import retry service.
        def retry_batch
          ::Admin::Candidates::Imports::RetryService.call(actor: current_user, batch: import_batch,
                                                          request_id: request.request_id)
        end

        # Schedules the background job that actually re-processes the
        # import batch.
        def enqueue(batch)
          ::Admin::CandidateImports::ExecuteJob.perform_later(batch.public_id, request.request_id)
        end
      end
    end
  end
end
