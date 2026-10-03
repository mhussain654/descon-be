# frozen_string_literal: true

module CandidateWorkflows
  # Staff view of one medical result (includes who recorded it, by role only).
  class AdminMedicalResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      MedicalResultSerializer.new(@result).as_json.merge(
        note: @result.note,
        recorded_by: { id: @result.recorded_by.public_id, role: @result.recorded_by.role }
      )
    end
  end
end
