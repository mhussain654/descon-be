# frozen_string_literal: true

module CandidateWorkflows
  class AdminFlightDetailSerializer
    def initialize(detail)
      @detail = detail
    end

    def as_json(*)
      return if @detail.blank?

      FlightDetailSerializer.new(@detail).as_json.merge(
        recorded_by: serialized_actor(@detail.recorded_by),
        mobilized_recorded_by: serialized_actor(@detail.mobilized_recorded_by)
      )
    end

    private

    def serialized_actor(actor)
      return if actor.blank?

      { id: actor.public_id, role: actor.role }
    end
  end
end
