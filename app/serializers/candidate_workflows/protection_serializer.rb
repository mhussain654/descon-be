# frozen_string_literal: true

module CandidateWorkflows
  class ProtectionSerializer
    def initialize(record)
      @record = record
    end

    def as_json(*)
      return if @record.blank?

      {
        id: @record.public_id,
        appeared_on: serialize_date(@record.appeared_on),
        appeared_recorded_at: serialize_time(@record.appeared_recorded_at),
        protected_on: serialize_date(@record.protected_on),
        ready_to_fly_at: serialize_time(@record.ready_to_fly_at)
      }
    end

    private

    def serialize_date(value)
      value&.iso8601
    end

    def serialize_time(value)
      value&.utc&.iso8601
    end
  end
end
