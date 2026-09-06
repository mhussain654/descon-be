# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff bulk-import candidates from a file, preview/validate before committing,
      # and review past import batches and their row-level errors.
      class CandidateImportsController < ProtectedStaffController
        # Returns a paginated, filtered list of past candidate import batches.
        def index
          authorize ::CandidateImportBatch, :index?, policy_class: ::Admin::CandidateImportPolicy

          render_history
        end

        # Returns a single import batch's details, including its per-row results.
        def show
          authorize import_batch, :show?, policy_class: ::Admin::CandidateImportPolicy

          set_private_state_headers(updated_at: import_batch.updated_at, etag_key: import_batch.public_id)
          render_success(data: serialized_batch(import_batch, include_rows: true))
        end

        # Runs the uploaded file straight through the import service and returns the batch result.
        def create
          authorize :candidate_import, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.create', subject: current_user) do
            import_payload
          end
        end

        # Validates the uploaded file without persisting candidates, returning a preflight token
        # and row-level validation results for review before committing.
        def preflight
          authorize :candidate_import, :preflight?, policy_class: ::Admin::CandidateImportPolicy
          result = ::Admin::Candidates::Imports::PreflightService.call(
            actor: current_user,
            file: import_params.fetch(:file),
            request_id: request.request_id
          )
          render_success_payload(success_payload(data: result, status: :created))
        end

        # Commits a previously validated preflight (by token), idempotently, actually creating candidates.
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

        # Streams a CSV of the row-level errors for an import batch as a file download.
        def error_export
          authorize import_batch, :error_export?, policy_class: ::Admin::CandidateImportPolicy

          response.set_header('Cache-Control', 'private, no-store')
          send_data ::Admin::CandidateImports::ErrorExport.new(import_batch).to_csv,
                    filename: "candidate-import-#{import_batch.public_id}-errors.csv", type: 'text/csv; charset=utf-8',
                    disposition: 'attachment'
        end

        private

        # Queries and renders the paginated list of import batches within the staff member's scope.
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

        # Runs the import service on the uploaded file and builds the response body, using 201 when
        # at least one row succeeded and 200 otherwise.
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

        # Allowlists the uploaded file field for create/preflight.
        def import_params
          params.expect(candidate_import: [:file])
        end

        # Allowlists the preflight token field for commit.
        def commit_params
          params.expect(candidate_import: [:preflight_token])
        end

        # Loads the import batch named in the route within the staff member's authorized scope,
        # raising if not found.
        def import_batch
          @import_batch ||= import_batches_scope.find_by!(public_id: params.expect(:id))
        end

        # Scopes import batches to what the current staff member is authorized to see.
        def import_batches_scope
          policy_scope(::CandidateImportBatch, policy_scope_class: ::Admin::CandidateImportPolicy::Scope)
        end

        # Serializes an import batch, optionally including its per-row results.
        def serialized_batch(batch, include_rows: false)
          ::Admin::CandidateImports::BatchSerializer.new(batch, include_rows:).as_json
        end
      end
    end
  end
end
