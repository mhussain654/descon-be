# frozen_string_literal: true

module CandidateWorkflows
  class FlightTicketAccessSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        flight_detail_id: @result.detail.public_id,
        url: @result.url,
        expires_at: @result.expires_at
      }
    end
  end
end
