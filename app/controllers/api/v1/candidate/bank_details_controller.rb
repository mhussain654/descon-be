# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class BankDetailsController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::BankDetailPolicy

          summary = ::Candidates::BankDetails::FetchService.call(candidate: current_candidate)
          render_success(data: ::Candidates::BankDetailSerializer.new(summary).as_json)
        end

        def update
          authorize current_candidate, policy_class: ::Candidates::BankDetailPolicy

          render_idempotent_response(
            scope: 'candidate.bank_details.update',
            subject: current_candidate,
            fingerprint: upload_fingerprint
          ) do
            update_payload
          end
        end

        private

        def update_payload
          result = ::Candidates::BankDetails::UpsertService.call(
            candidate: current_candidate,
            account_title: bank_detail_params[:account_title],
            account_number: bank_detail_params[:account_number],
            bank_name: bank_detail_params[:bank_name],
            proof: bank_detail_params[:proof],
            request_id: request.request_id
          )
          summary = ::Candidates::BankDetails::BankDetailSummary.new(status: result.bank_detail.status_code, bank_detail: result.bank_detail)

          success_payload(
            data: ::Candidates::BankDetailSerializer.new(summary).as_json.merge(message: success_message(result)),
            status: result.created? ? :created : :ok
          )
        end

        def upload_fingerprint
          return if request.headers['Idempotency-Key'].blank?

          ::Candidates::BankDetails::UploadFingerprint.call(
            request:,
            uploaded_file: bank_detail_params[:proof],
            account_title: bank_detail_params[:account_title],
            account_number: bank_detail_params[:account_number],
            bank_name: bank_detail_params[:bank_name]
          )
        end

        def bank_detail_params
          params.expect(bank_detail: %i[account_title account_number bank_name proof])
        end

        def success_message(result)
          result.created? ? t('api.candidate_bank_details.submitted') : t('api.candidate_bank_details.updated')
        end
      end
    end
  end
end
