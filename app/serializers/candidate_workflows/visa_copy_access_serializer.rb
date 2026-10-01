# frozen_string_literal: true

module CandidateWorkflows
  # Shared by both the staff and candidate visa-copy-access endpoints --
  # mirrors FlightTicketAccessSerializer exactly.
  class VisaCopyAccessSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        visa_decision_id: @result.decision.public_id,
        url: @result.url,
        expires_at: @result.expires_at
      }
    end
  end
end
