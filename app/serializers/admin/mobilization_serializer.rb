# frozen_string_literal: true

module Admin
  # One row of the admin Mobilization list: the candidate, their flight, and
  # where they stand on the ticket, boarding pass and mobilization. Never
  # includes file URLs (see FlightTicketAccessService for those).
  class MobilizationSerializer
    def initialize(detail)
      @detail = detail
    end

    def as_json(*)
      { id: @detail.public_id, candidate: candidate_attributes(@detail.candidate_assignment) }
        .merge(flight_attributes, progress_attributes)
    end

    private

    def flight_attributes
      {
        airline: @detail.airline,
        flight_number: @detail.flight_number,
        sector: @detail.sector,
        flight_departure_at: @detail.flight_departure_at.utc.iso8601
      }
    end

    def progress_attributes
      {
        ticket_attached: @detail.ticket.attached?,
        boarding_pass_uploaded_at: @detail.boarding_pass_uploaded_at&.utc&.iso8601,
        boarding_pass_check: CandidateWorkflows::BoardingPassCheckSerializer.new(@detail).as_json,
        boarding_pass_rejected: @detail.boarding_pass_rejected?,
        mobilized_on: @detail.mobilized_on&.iso8601,
        status: @detail.departure_status
      }
    end

    def candidate_attributes(assignment)
      {
        id: assignment.candidate.public_id,
        full_name: assignment.candidate.full_name,
        reference_number: assignment.reference_number,
        country_name: assignment.country&.name_for,
        project_name: assignment.project&.name_for,
        craft_name: assignment.craft&.name_for
      }
    end
  end
end
