# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateImportRetriesController < ProtectedStaffController
        def create
          authorize import_batch, :retry?, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.retry', subject: current_user) do
            retry_payload
          end
        end

        private

        def import_batch
          policy_scope(::CandidateImportBatch, policy_scope_class: ::Admin::CandidateImportPolicy::Scope)
            .find_by!(public_id: params.expect(:candidate_import_id))
        end

        def retry_payload
          batch = retry_batch
          enqueue(batch)
          set_private_state_headers(updated_at: batch.updated_at, etag_key: batch.public_id)
          success_payload(data: ::Admin::CandidateImports::BatchSerializer.new(batch).as_json, status: :accepted)
        end

        def retry_batch
          ::Admin::Candidates::Imports::RetryService.call(actor: current_user, batch: import_batch,
                                                          request_id: request.request_id)
        end

        def enqueue(batch)
          ::Admin::CandidateImports::ExecuteJob.perform_later(batch.public_id, request.request_id)
        end
      end
    end
  end
end
