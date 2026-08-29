# frozen_string_literal: true

module CandidateWorkflows
  PrerequisiteResult = Data.define(:allowed, :field, :required_fields, :blocking_reasons) do
    def self.allowed(required_fields:)
      new(
        allowed: true,
        field: nil,
        required_fields:,
        blocking_reasons: []
      )
    end

    def self.blocked(field:, blocking_reasons:, required_fields:)
      new(
        allowed: false,
        field:,
        required_fields:,
        blocking_reasons:
      )
    end
  end
end
