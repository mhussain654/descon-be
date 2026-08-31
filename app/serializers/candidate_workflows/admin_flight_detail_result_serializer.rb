# frozen_string_literal: true

module CandidateWorkflows
  class AdminFlightDetailResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        workflow: StateSerializer.new(@result.fetch(:snapshot)).as_json,
        flight_detail: AdminFlightDetailSerializer.new(@result.fetch(:flight_detail)).as_json
      }
    end
  end
end
