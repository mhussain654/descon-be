# frozen_string_literal: true

module Candidates
  class BankDetailSerializer
    def initialize(summary)
      @summary = summary
    end

    def as_json(*)
      {
        status: @summary.status,
        bank_detail: serialized_bank_detail
      }
    end

    private

    def serialized_bank_detail
      return if bank_detail.blank?

      identity_attributes
        .merge(account_attributes)
        .merge(proof: serialized_proof)
        .merge(timestamp_attributes)
    end

    def serialized_proof
      {
        file_name: bank_detail.proof_filename,
        content_type: bank_detail.proof_content_type,
        file_size: bank_detail.proof_byte_size,
        uploaded_at: bank_detail.submitted_at.utc.iso8601
      }
    end

    def masked_account_number
      Candidates::BankDetails::AccountNumberMasker.call(account_number: bank_detail.account_number)
    end

    def bank_detail
      @summary.bank_detail
    end

    def identity_attributes
      {
        id: bank_detail.public_id,
        status: bank_detail.status_code
      }
    end

    def account_attributes
      {
        account_title: bank_detail.account_title,
        account_number: masked_account_number,
        bank_name: bank_detail.bank_name
      }
    end

    def timestamp_attributes
      {
        submitted_at: bank_detail.submitted_at.utc.iso8601,
        updated_at: bank_detail.updated_at.utc.iso8601
      }
    end
  end
end
