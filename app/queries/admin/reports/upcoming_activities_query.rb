# frozen_string_literal: true

module Admin
  module Reports
    # Everything happening across QVC appointments and flight departures in
    # the next 7 days (admin dashboard redesign). Protection appearances are
    # deliberately excluded: CandidateProtectionRecord has no forward-
    # scheduled date column today (only `appeared_on`, set once the
    # appearance already happened) -- adding one is tracked as a later phase
    # of the redesign, not silently approximated here.
    class UpcomingActivitiesQuery < ApplicationQuery
      WINDOW = 7.days

      def initialize(scope: Candidate.all, reference_time: Time.current)
        super()
        @scope = scope
        @reference_time = reference_time
      end

      def call
        (qvc_appointments + flight_departures).sort_by { |item| item.fetch(:occurs_on) }
      end

      private

      def qvc_appointments
        CandidateQvcAttempt
          .open_attempts
          .where(candidate_assignment_id: assignment_ids)
          .where(appointment_date: @reference_time.to_date..(@reference_time + WINDOW).to_date)
          .includes(:candidate_assignment)
          .map { |attempt| activity_row('qvc_appointment', attempt.appointment_date, attempt.candidate_assignment) }
      end

      def flight_departures
        CandidateFlightDetail
          .where(candidate_assignment_id: assignment_ids)
          .where(flight_departure_at: @reference_time..(@reference_time + WINDOW))
          .includes(:candidate_assignment)
          .map do |flight|
          activity_row('flight_departure', flight.flight_departure_at.to_date,
                       flight.candidate_assignment)
        end
      end

      def activity_row(type, occurs_on, assignment)
        {
          type: type,
          occurs_on: occurs_on,
          candidate_assignment_public_id: assignment.public_id,
          reference_number: assignment.reference_number
        }
      end

      def assignment_ids
        @assignment_ids ||= CurrentAssignmentJoin.call(scope: @scope).select('current_assignments.id')
      end
    end
  end
end
