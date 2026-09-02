# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateImportsController < ProtectedStaffController
        def index
          authorize ::CandidateImportBatch, :index?, policy_class: ::Admin::CandidateImportPolicy

          render_history
        end

        def show
          authorize import_batch, :show?, policy_class: ::Admin::CandidateImportPolicy

          set_private_state_headers(updated_at: import_batch.updated_at, etag_key: import_batch.public_id)
          render_success(data: serialized_batch(import_batch, include_rows: true))
        end

        def create
          authorize :candidate_import, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.create', subject: current_user) do
            import_payload
          end
        end

        def preflight
          authorize :candidate_import, :preflight?, policy_class: ::Admin::CandidateImportPolicy
          result = ::Admin::Candidates::Imports::PreflightService.call(
            actor: current_user,
            file: import_params.fetch(:file),
            request_id: request.request_id
          )
          render_success_payload(success_payload(data: result, status: :created))
        end

        def commit
          authorize :candidate_import, :commit?, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.commit', subject: current_user) do
            result = ::Admin::Candidates::Imports::CommitService.call(
              actor: current_user,
              token: commit_params.fetch(:preflight_token),
              request_id: request.request_id,
              idempotency_key: request.headers['Idempotency-Key']
            )
            success_payload(data: result, status: :accepted)
          end
        end

        def error_export
          authorize import_batch, :error_export?, policy_class: ::Admin::CandidateImportPolicy

          response.set_header('Cache-Control', 'private, no-store')
          send_data ::Admin::CandidateImports::ErrorExport.new(import_batch).to_csv,
                    filename: "candidate-import-#{import_batch.public_id}-errors.csv", type: 'text/csv; charset=utf-8',
                    disposition: 'attachment'
        end

        private

        def render_history
          query = ::Admin::CandidateImports::IndexQuery.new(
            scope: import_batches_scope,
            params:
          )
          batches = query.call
          set_private_state_headers(
            updated_at: batches.maximum(:updated_at), etag_key: "candidate-imports:#{current_user.public_id}"
          )
          render_collection(data: batches.map { |batch| serialized_batch(batch) }, pagination: query.pagination,
                            meta: { applied_filters: query.applied_filters })
        end

        def import_payload
          result = ::Admin::Candidates::ImportService.call(
            actor: current_user,
            file: import_params.fetch(:file),
            request_id: request.request_id
          )

          success_payload(
            data: ::Admin::CandidateImports::ResultSerializer.new(result).as_json,
            status: result.fetch(:successful_rows).positive? ? :created : :ok
          )
        end

        def import_params
          params.expect(candidate_import: [:file])
        end

        def commit_params
          params.expect(candidate_import: [:preflight_token])
        end

        def import_batch
          @import_batch ||= import_batches_scope.find_by!(public_id: params.expect(:id))
        end

        def import_batches_scope
          policy_scope(::CandidateImportBatch, policy_scope_class: ::Admin::CandidateImportPolicy::Scope)
        end

        def serialized_batch(batch, include_rows: false)
          ::Admin::CandidateImports::BatchSerializer.new(batch, include_rows:).as_json
        end
      end
    end
  end
end
