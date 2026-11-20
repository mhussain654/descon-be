# frozen_string_literal: true

module Admin
  module Mobilizations
    # Applies one Mobilization-list filter to a CandidateFlightDetail scope,
    # rejecting values the list does not support.
    class FilterScope
      BOARDING_PASS_STATES = %w[uploaded missing].freeze
      STATUS_STATES = %w[awaiting_departure mobilized].freeze
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

      def status(state)
        return @scope.where.not(mobilized_on: nil) if state == 'mobilized'

        @scope.where(mobilized_on: nil)
      end
    end
  end
end
