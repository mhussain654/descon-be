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
      end
    end
  end
end
