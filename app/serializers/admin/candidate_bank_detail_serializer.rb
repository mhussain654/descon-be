# frozen_string_literal: true

module Admin
  class CandidateBankDetailSerializer
    def initialize(bank_detail, reveal_account_number: false)
      @bank_detail = bank_detail
      @reveal_account_number = reveal_account_number
    end

    def as_json(*)
      primary_attributes
        .merge(
          candidate: serialized_candidate,
          assignment: serialized_assignment
        )
        .merge(account_attributes)
        .merge(
          proof: serialized_proof
        )
        .merge(timestamp_attributes)
    end

    private

    def primary_attributes
      {
        id: @bank_detail.public_id,
        status: @bank_detail.status_code
      }
    end

    def serialized_candidate
      candidate = @bank_detail.candidate_assignment.candidate

      {
        id: candidate.public_id,
        full_name: candidate.full_name
      }
    end

    def serialized_assignment
      assignment = @bank_detail.candidate_assignment

      {
        id: assignment.public_id,
        reference_number: assignment.reference_number
      }
    end

    def serialized_account_number
      return @bank_detail.account_number if @reveal_account_number

      ::Candidates::BankDetails::AccountNumberMasker.call(account_number: @bank_detail.account_number)
    end

    def account_attributes
      {
        account_title: @bank_detail.account_title,
        account_number: serialized_account_number,
        bank_name: @bank_detail.bank_name
      }
    end

    def serialized_proof
      {
        file_name: @bank_detail.proof_filename,
        content_type: @bank_detail.proof_content_type,
        file_size: @bank_detail.proof_byte_size,
        uploaded_at: submitted_at
      }
    end

    def submitted_at
      @bank_detail.submitted_at.utc.iso8601
    end

    def updated_at
      @bank_detail.updated_at.utc.iso8601
    end

    def timestamp_attributes
      {
        submitted_at: submitted_at,
        updated_at: updated_at
      }
    end
  end
end
