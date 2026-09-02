# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateImportsController < ProtectedStaffController
        def create
          authorize :candidate_import, policy_class: ::Admin::CandidateImportPolicy

          render_idempotent_response(scope: 'admin.candidate_imports.create', subject: current_user) do
            import_payload
          end
        end

        def preflight
          authorize :candidate_import, :preflight?, policy_class: ::Admin::CandidateImportPolicy
          result = ::Admin::Candidates::Imports::PreflightService.call(actor: current_user, file: import_params.fetch(:file), request_id: request.request_id)
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
            success_payload(data: result, status: :ok)
          end
        end

        private

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
      end
    end
  end
end
