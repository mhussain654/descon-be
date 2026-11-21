# frozen_string_literal: true

module CandidateWorkflows
  # Staff-only: what the automatic OCR check found on the uploaded boarding pass
  # (CandidateFlightDetail::BOARDING_PASS_CHECKS). nil before any upload, or for
  # an upload made before the check existed.
  class BoardingPassCheckSerializer
    SIGNALS = %w[flight_number date name seat].freeze

    def initialize(detail)
      @detail = detail
    end

    def as_json(*)
      return if @detail.boarding_pass_check.blank?

      {
        result: @detail.boarding_pass_check,
        seat: @detail.boarding_pass_seat,
        signals: SIGNALS.index_with { |name| @detail.boarding_pass_check_signals[name] == true },
        checked_at: @detail.boarding_pass_checked_at&.utc&.iso8601
      }
    end
  end
end
