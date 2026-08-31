# frozen_string_literal: true

module CandidateWorkflows
  # Shared shape for both the staff and candidate flight-detail views --
  # neither surface needs internal actor ids beyond role, and neither ever
  # includes the ticket's blob/URL (see FlightTicketAccessService for the
  # separate, short-lived, authorized way to fetch it).
  class FlightDetailSerializer
    def initialize(detail)
      @detail = detail
    end

    def as_json(*)
      return if @detail.blank?

      flight_attributes.merge(mobilization_attributes)
    end

    private

    def flight_attributes
      {
        id: @detail.public_id,
        airline: @detail.airline,
        flight_number: @detail.flight_number,
        sector: @detail.sector,
        flight_departure_at: @detail.flight_departure_at.utc.iso8601,
        ticket_attached: @detail.ticket.attached?
      }
    end

    def mobilization_attributes
      { mobilized_on: @detail.mobilized_on&.iso8601, mobilized: @detail.mobilized? }
    end
  end
end
