# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # Corrects a candidate's flight -- airline, flight number, route, departure
    # (Pakistan time) -- and optionally replaces the ticket, until the candidate
    # is mobilized.
    class FlightDetailService < BaseService
      TICKET_FIELD = 'workflow_correction.ticket'
      TICKET_MAX_BYTES = 10.megabytes

      private

      def blocked_reason = status.flight_blocked_reason
      def audited_record = status.flight_detail
      def action_code = 'flight_detail_corrected'
      def sms_message_code = 'flight_details_changed'

      def apply!
        detail = status.flight_detail
        corrected = corrected_values
        changes = changed_fields(current_values(detail), corrected)
        detail.update!(corrected.merge('flight_departure_at' => Time.iso8601(corrected['flight_departure_at'])))
        replace_ticket!(detail, changes)
        changes
      end

      def current_values(detail)
        { 'airline' => detail.airline, 'flight_number' => detail.flight_number, 'sector' => detail.sector,
          'flight_departure_at' => detail.flight_departure_at.utc.iso8601 }
      end

      def corrected_values
        values = { 'airline' => text(:airline), 'flight_number' => text(:flight_number), 'sector' => text(:sector),
                   'flight_departure_at' => departure }
        raise_invalid!(:airline) if values['airline'].nil?
        raise_invalid!(:flight_number) if values['flight_number'].nil?
        values
      end

      # A departure without a zone is Pakistan time, the same as when it was first recorded.
      def departure
        normalized = FlightDetails::PakistanDepartureTime.normalize(@values[:flight_date].to_s.strip.presence)
        Time.iso8601(normalized.to_s).utc.iso8601
      rescue ArgumentError
        raise ValidationError.new(field: 'workflow_correction.flight_date',
                                  message: I18n.t('api.errors.workflow_transition_evidence_date_invalid'))
      end

      def replace_ticket!(detail, changes)
        ticket = @values[:ticket]
        return if ticket.blank?

        validate_ticket!(ticket)
        detail.ticket.attach(ticket)
        changes['ticket'] = [nil, 'replaced']
      end

      def validate_ticket!(ticket)
        raise MissingFileError.new(field: TICKET_FIELD) unless ticket.respond_to?(:tempfile)
        raise EmptyFileError.new(field: TICKET_FIELD) if ticket.size.to_i.zero?
        raise FileTooLargeError.new(field: TICKET_FIELD) if ticket.size.to_i > TICKET_MAX_BYTES
        raise UnsupportedFileTypeError.new(field: TICKET_FIELD) unless allowed_ticket_type?(ticket)
      end

      # Judged by the file's own content (a PDF, JPEG or PNG), never its name.
      def allowed_ticket_type?(ticket)
        content_type = Candidates::Documents::UploadedFileInspector.call(uploaded_file: ticket).content_type
        DocumentRequirement::CONTENT_TYPES.include?(content_type)
      end

      def sms_variables
        departure = status.flight_detail.flight_departure_at.in_time_zone(Status::PAKISTAN_TIME_ZONE)
        { date: CandidateSms::ScheduleDelivery.format_date(departure), time: departure.strftime('%H:%M') }
      end
    end
  end
end
