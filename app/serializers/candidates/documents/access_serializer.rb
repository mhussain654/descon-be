# frozen_string_literal: true

module Candidates
  module Documents
    # Mirrors CandidateWorkflows::VisaCopyAccessSerializer/FlightTicketAccessSerializer exactly.
    class AccessSerializer
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
end
