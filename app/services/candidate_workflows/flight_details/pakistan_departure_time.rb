# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    # Staff type a flight's departure as the local Pakistan date and time (the form sends it without an
    # offset, e.g. 2026-11-20T14:30), so a time without an offset is read as Pakistan time; one with an
    # offset is kept as that moment. Returns it with its offset (2026-11-20T14:30:00+05:00), or the value as
    # given when it does not parse, for the caller's own validation to refuse.
    module PakistanDepartureTime
      ZONE = ActiveSupport::TimeZone['Asia/Karachi']

      module_function

      def normalize(value)
        ZONE.iso8601(value.to_s).iso8601
      rescue ArgumentError
        value.to_s
      end
    end
  end
end
