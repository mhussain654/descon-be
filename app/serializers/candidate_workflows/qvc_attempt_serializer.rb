# frozen_string_literal: true

module CandidateWorkflows
  class QvcAttemptSerializer
    def initialize(attempt)
      @attempt = attempt
    end

    def as_json(*)
      {
        id: @attempt.public_id,
        attempt_number: @attempt.attempt_number,
        appointment_date: @attempt.appointment_date.iso8601,
        outcome_code: @attempt.outcome_code,
        no_show: @attempt.no_show,
        outcome_recorded_at: @attempt.outcome_recorded_at&.utc&.iso8601,
        status: status
      }
    end

    private

    def status
      return 'no_show' if @attempt.no_show?
      return @attempt.outcome_code if @attempt.outcome_code.present?

      'scheduled'
    end
  end
end
