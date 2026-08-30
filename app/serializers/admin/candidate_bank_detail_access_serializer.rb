# frozen_string_literal: true

module Admin
  class CandidateBankDetailAccessSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        bank_detail_id: @result.bank_detail.public_id,
        url: @result.url,
        expires_at: @result.expires_at
      }
    end
  end
end
