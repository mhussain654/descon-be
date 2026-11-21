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
      {
        mobilized_on: @detail.mobilized_on&.iso8601,
        mobilized: @detail.mobilized?,
        boarding_pass_uploaded_at: @detail.boarding_pass_uploaded_at&.utc&.iso8601,
        boarding_pass_upload: boarding_pass_upload_window
      }
    end

    # When the candidate may upload their boarding pass (Pakistan days), and
    # where today falls, so the app needn't trust the phone's clock.
    def boarding_pass_upload_window
      {
        opens_on: @detail.boarding_pass_upload_opens_on.iso8601,
        closes_on: @detail.boarding_pass_upload_closes_on.iso8601,
        state: @detail.boarding_pass_upload_state
      }
    end
  end
end
