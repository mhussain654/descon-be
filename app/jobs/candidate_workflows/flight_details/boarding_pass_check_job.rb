# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    # Reads a just-uploaded boarding pass photo with OCR and records whether it
    # matches the booked flight (BoardingPassMatcher). Runs for one upload,
    # named by its upload time, so a run for a photo that has since been
    # replaced does nothing. Keeps only the result, the signals and the seat,
    # never the OCR text. When OCR is off or can't read the photo the check is
    # `unavailable`, and the upload counts as it did before the check existed.
    class BoardingPassCheckJob < ApplicationJob
      queue_as :default

      QUERIES = [
        { text: 'What is the flight number?', alias: 'FLIGHT' },
        { text: 'What is the date of the flight?', alias: 'DATE' },
        { text: 'What is the passenger name?', alias: 'NAME' },
        { text: 'What is the seat number?', alias: 'SEAT' }
      ].freeze

      retry_on DocumentOcr::TransientError, wait: :polynomially_longer, attempts: 3 do |job, _error|
        job.record_unavailable(*job.arguments)
      end

      def perform(flight_detail_id, uploaded_at)
        detail = current_upload(flight_detail_id, uploaded_at)
        return if detail.nil?

        result = BoardingPassMatcher.call(**match_inputs(detail, read(detail)))
        detail.update!(boarding_pass_check: result[:check], boarding_pass_check_signals: result[:signals],
                       boarding_pass_seat: result[:seat], boarding_pass_checked_at: Time.current)
      rescue DocumentOcr::PermanentError
        record_unavailable(flight_detail_id, uploaded_at)
      end

      def record_unavailable(flight_detail_id, uploaded_at)
        current_upload(flight_detail_id, uploaded_at)
          &.update!(boarding_pass_check: 'unavailable', boarding_pass_checked_at: Time.current)
      end

      private

      def current_upload(flight_detail_id, uploaded_at)
        detail = CandidateFlightDetail.find_by(id: flight_detail_id)
        return if detail&.boarding_pass_uploaded_at.nil? || !detail.boarding_pass.attached?
        return unless detail.boarding_pass_uploaded_at.utc.iso8601(6) == uploaded_at

        detail
      end

      def read(detail)
        raise DocumentOcr::PermanentError, 'OCR is off' unless DocumentOcr::TextractAdapter.enabled?

        DocumentOcr::TextractAdapter.new.read_text(bytes: detail.boarding_pass.download, queries: QUERIES)
      end

      def match_inputs(detail, ocr)
        {
          lines: ocr[:lines], answers: ocr[:answers], flight_number: detail.flight_number,
          flight_day: detail.departure_date_in_pakistan,
          full_name: detail.candidate_assignment.candidate.full_name
        }
      end
    end
  end
end
