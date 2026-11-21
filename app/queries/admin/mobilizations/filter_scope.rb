# frozen_string_literal: true

module Admin
  module Mobilizations
    # Applies one Mobilization-list filter to a CandidateFlightDetail scope,
    # rejecting values the list does not support.
    class FilterScope
      BOARDING_PASS_STATES = %w[uploaded missing].freeze
      STATUS_STATES = CandidateFlightDetail::DEPARTURE_STATUSES
      # Candidates fly out of Pakistan, so a flight date is a calendar day in
      # Pakistan time, not UTC (a 02:00 PKT departure is 21:00 UTC the day before).
      FLIGHT_DATE_TIME_ZONE = 'Asia/Karachi'

      def self.call(scope, name, value) = new(scope).apply(name, value)

      def initialize(scope)
        @scope = scope
      end

      def apply(name, value)
        case name
        when 'flight_date' then flight_date(value)
        when 'country_code' then country(value)
        when *RegisteredDateFilter::NAMES
          @scope.where(candidates: { created_at: RegisteredDateFilter.range(name, value) })
        when 'boarding_pass' then boarding_pass(normalized(value, BOARDING_PASS_STATES, name))
        else status(normalized(value, STATUS_STATES, name))
        end
      end

      private

      def normalized(value, allowed, name)
        state = value.to_s.strip.downcase
        raise InvalidQueryParameterError.new(field: "filter.#{name}") unless allowed.include?(state)

        state
      end

      def flight_date(value)
        date = Date.iso8601(value.to_s.strip)
        @scope.where(flight_departure_at: Time.find_zone!(FLIGHT_DATE_TIME_ZONE)
                                              .local(date.year, date.month, date.day).all_day)
      rescue Date::Error
        raise InvalidQueryParameterError.new(field: 'filter.flight_date')
      end

      def country(code)
        country = Country.find_by(code: code.to_s.strip.downcase)
        raise InvalidQueryParameterError.new(field: 'filter.country_code') if country.blank?

        @scope.where(candidate_assignments: { country_id: country.id })
      end

      def boarding_pass(state)
        return @scope.where.not(boarding_pass_uploaded_at: nil) if state == 'uploaded'

        @scope.where(boarding_pass_uploaded_at: nil)
      end

      # The same rule as CandidateFlightDetail#departure_status, in SQL.
      def status(state)
        return departed if state == 'departed'

        case state
        when 'departing_today' then not_departed.where(flight_departure_at: today_starts_at...tomorrow_starts_at)
        when 'scheduled' then not_departed.where(flight_departure_at: tomorrow_starts_at..)
        else not_departed.where(flight_departure_at: ...today_starts_at).where.not(id: confirming_boarding_pass_ids)
        end
      end

      def not_departed = @scope.where(mobilized_on: nil).or(@scope.where(mobilized_on: (today + 1)..))

      def departed
        @scope.where(mobilized_on: ..today)
              .or(@scope.where(flight_departure_at: ...today_starts_at, id: confirming_boarding_pass_ids))
      end

      # CandidateFlightDetail#boarding_pass_confirms_departure?, in SQL.
      def confirming_boarding_pass_ids
        CandidateFlightDetail.where.not(boarding_pass_uploaded_at: nil)
                             .where(boarding_pass_rejected_at: nil,
                                    boarding_pass_check: CandidateFlightDetail::BOARDING_PASS_CONFIRMING_CHECKS)
                             .select(:id)
      end

      def today = @today ||= CandidateFlightDetail.pakistan_today
      def today_starts_at = Time.find_zone!(FLIGHT_DATE_TIME_ZONE).local(today.year, today.month, today.day)
      def tomorrow_starts_at = today_starts_at + 1.day
    end
  end
end
