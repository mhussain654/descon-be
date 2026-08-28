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
      return if @summary.bank_detail.blank?

      {
        id: @summary.bank_detail.public_id,
        status: @summary.bank_detail.status_code,
        account_title: @summary.bank_detail.account_title,
        account_number: masked_account_number,
        bank_name: @summary.bank_detail.bank_name,
        proof: serialized_proof,
        submitted_at: @summary.bank_detail.submitted_at.utc.iso8601,
        updated_at: @summary.bank_detail.updated_at.utc.iso8601
      }
    end

    def serialized_proof
      {
        file_name: @summary.bank_detail.proof_filename,
        content_type: @summary.bank_detail.proof_content_type,
        file_size: @summary.bank_detail.proof_byte_size,
        uploaded_at: @summary.bank_detail.submitted_at.utc.iso8601
      }
    end

    def masked_account_number
      Candidates::BankDetails::AccountNumberMasker.call(account_number: @summary.bank_detail.account_number)
    end
  end
end
