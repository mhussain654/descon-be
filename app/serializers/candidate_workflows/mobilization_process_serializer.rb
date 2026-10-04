# frozen_string_literal: true

module CandidateWorkflows
  # Which process version a candidate's workflow follows. `provisional` marks
  # the common fallback used until a country's requirements are confirmed.
  class MobilizationProcessSerializer
    def initialize(process)
      @process = process
    end

    def as_json(*)
      return if @process.blank?

      {
        code: @process.code,
        version: @process.version,
        provisional: @process.provisional,
        country_code: @process.country&.code
      }
    end
  end
end
