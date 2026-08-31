# frozen_string_literal: true

module CandidateWorkflows
  class AdminVisaDecisionResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        workflow: StateSerializer.new(@result.fetch(:snapshot)).as_json,
        visa_decision: AdminVisaDecisionSerializer.new(@result.fetch(:visa_decision)).as_json
      }
    end
  end
end
