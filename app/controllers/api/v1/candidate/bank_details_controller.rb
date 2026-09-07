# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate view and submit their own bank account details.
      class BankDetailsController < ProtectedController
        # Returns the candidate's current bank detail submission and its review status.
        def show
          authorize current_candidate, policy_class: ::Candidates::BankDetailPolicy

          summary = ::Candidates::BankDetails::FetchService.call(candidate: current_candidate)
          render_success(data: ::Candidates::BankDetailSerializer.new(summary).as_json)
        end

        # Creates or replaces the candidate's bank details (with proof upload), idempotently.
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

        # Builds the success response body for an update, using 201 on first submission and 200 on edits.
        def update_payload
          result = upsert_result

          success_payload(
            data: serialized_update_result(result),
            status: result.created? ? :created : :ok
          )
        end

        # Serializes the upsert result and appends a localized success message.
        def serialized_update_result(result)
          ::Candidates::BankDetailSerializer.new(bank_detail_summary(result)).as_json.merge(
            message: success_message(result)
          )
        end

        # Creates or updates the bank detail record via the upsert service, memoized per request.
        def upsert_result
          @upsert_result ||= ::Candidates::BankDetails::UpsertService.call(
            candidate: current_candidate,
            attributes: bank_detail_attributes,
            request_id: request.request_id
          )
        end

        # Wraps the persisted bank detail and its status code for serialization.
        def bank_detail_summary(result)
          ::Candidates::BankDetails::BankDetailSummary.new(
            status: result.bank_detail.status_code,
            bank_detail: result.bank_detail
          )
        end

        # Computes an idempotency fingerprint from the request when an Idempotency-Key header is present.
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

        # Allowlists the bank detail fields (title, account number, bank name, proof file) from the request.
        def bank_detail_params
          params.expect(bank_detail: %i[account_title account_number bank_name proof])
        end

        # Converts the permitted bank detail params into a symbolized attributes hash.
        def bank_detail_attributes
          bank_detail_params.to_h.symbolize_keys
        end

        # Picks the localized "submitted" vs "updated" message based on whether this was a first submission.
        def success_message(result)
          result.created? ? t('api.candidate_bank_details.submitted') : t('api.candidate_bank_details.updated')
        end
      end
    end
  end
end
