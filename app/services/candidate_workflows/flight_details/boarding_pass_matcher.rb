# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    # Compares the text OCR read from a boarding pass photo with the flight staff
    # booked, to tell a real boarding pass for this flight from any other photo.
    # Every airline prints the flight number, the date and the passenger's name;
    # most also print a seat (or GATE/SBY when it is given at the gate), so the
    # seat only adds confidence and is never required.
    #
    # - matched: flight number, date and name all found;
    # - needs_review: only some of them found (staff should look);
    # - not_boarding_pass: neither the flight number nor the date found.
    #
    # Pure: takes the OCR text, keeps nothing of it but the seat.
    class BoardingPassMatcher
      MONTHS = %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC].freeze
      SEAT = /\A0?(\d{1,2}[A-K])\z/
      SEAT_AT_GATE = /\A(GATE|SBY|STBY)\z/
      MIN_NAME_PART_LENGTH = 3

      # lines: the page's text lines; answers: OCR answers keyed by query alias
      # (FLIGHT, DATE, NAME, SEAT); flight_number: as staff recorded it;
      # flight_day: the flight's day in Pakistan; full_name: the candidate's name.
      def self.call(...) = new(...).call

      def initialize(lines:, answers:, flight_number:, flight_day:, full_name:)
        @text = [*lines, *answers.values].join("\n").upcase
        @seat_answer = answers['SEAT'].to_s.upcase.delete(' ')
        @lines = lines.map(&:upcase)
        @flight_number = flight_number.to_s.upcase.gsub(/[^A-Z0-9]/, '')
        @flight_day = flight_day
        @full_name = full_name.to_s
      end

      def call
        seat = seat_found
        signals = { flight_number: flight_number_found?, date: date_found?, name: name_found?, seat: seat.present? }
        { check: check_for(signals), signals:, seat: }
      end

      private

      def check_for(signals)
        return signals[:name] ? 'matched' : 'needs_review' if signals[:flight_number] && signals[:date]
        return 'needs_review' if signals[:flight_number] || signals[:date]

        'not_boarding_pass'
      end

      # "QR-629" matches QR629, QR 629, QR-0629 or QR 0629.
      def flight_number_found?
        match = @flight_number.match(/\A([A-Z0-9]{2})0*(\d{1,4}[A-Z]?)\z/)
        return @flight_number.present? && @text.gsub(/[^A-Z0-9]/, '').include?(@flight_number) if match.nil?

        @text.match?(/(?<![A-Z0-9])#{match[1]}[\s-]*0*#{match[2]}(?![0-9])/)
      end

      # The flight's day in any common printed form: 20NOV, 20 NOV 2026, NOV 20,
      # 20/11/2026, 20.11.26 or 2026-11-20.
      def date_found? = date_patterns.any? { |pattern| @text.match?(pattern) }

      def date_patterns
        day = @flight_day.day
        month = @flight_day.month
        year = @flight_day.year
        name = MONTHS[month - 1]
        [
          %r{(?<!\d)0?#{day}[\s/.-]*#{name}},
          /#{name}[A-Z]*\.?\s*0?#{day}(?!\d)/,
          %r{(?<!\d)0?#{day}[/.-]0?#{month}[/.-](?:#{year}|#{format('%02d', year % 100)})(?!\d)},
          %r{#{year}[/.-]0?#{month}[/.-]0?#{day}(?!\d)}
        ]
      end

      # Airlines print SURNAME/GIVENNAMES, often run together or cut short, so
      # each part of the name is looked for in the letters alone, and two parts
      # are enough (one for a one-word name).
      def name_found?
        parts = @full_name.upcase.split(/[^A-Z]+/).select { |part| part.length >= MIN_NAME_PART_LENGTH }.uniq
        return false if parts.empty?

        letters = @text.gsub(/[^A-Z]/, '')
        parts.count { |part| letters.include?(part) } >= [parts.size, 2].min
      end

      def seat_found
        return normalized_seat(@seat_answer) if normalized_seat(@seat_answer)

        @lines.each_with_index do |line, index|
          next unless line.match?(/\bSEAT\b/)

          [line.split(/\bSEAT\b/, 2).last, @lines[index + 1]].compact.each do |candidate|
            seat = candidate.split.lazy.filter_map { |token| normalized_seat(token) }.first
            return seat if seat
          end
        end
        nil
      end

      def normalized_seat(value)
        token = value.to_s.gsub(/[^A-Z0-9]/, '')
        return token.match(SEAT)[1] if token.match?(SEAT)

        token if token.match?(SEAT_AT_GATE)
      end
    end
  end
end
