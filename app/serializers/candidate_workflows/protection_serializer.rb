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
        appeared_on: @record.appeared_on&.iso8601,
        appeared_recorded_at: @record.appeared_recorded_at&.utc&.iso8601,
        protected_on: @record.protected_on&.iso8601,
        ready_to_fly_at: @record.ready_to_fly_at&.utc&.iso8601
      }
    end
  end
end
