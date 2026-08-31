# frozen_string_literal: true

module CandidateWorkflows
  class AdminQvcAttemptResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        workflow: StateSerializer.new(@result.fetch(:snapshot)).as_json,
        qvc_attempt: AdminQvcAttemptSerializer.new(@result.fetch(:qvc_attempt)).as_json
      }
    end
  end
end
