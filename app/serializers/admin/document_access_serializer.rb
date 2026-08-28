# frozen_string_literal: true

module Admin
  class DocumentAccessSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        document_id: @result.document.public_id,
        url: @result.url,
        expires_at: @result.expires_at
      }
    end
  end
end
