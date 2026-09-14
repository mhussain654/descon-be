# frozen_string_literal: true

module AiCalls
  module Tools
    class GetFlightInformation < VerifiedDataTool
      private

      def data
        serialized = ::CandidateWorkflows::FlightDetailSerializer.new(assignment.candidate_flight_detail).as_json
        serialized || { status: 'not_yet_available' }
      end
    end
  end
end
