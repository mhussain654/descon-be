# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    # Stores the candidate's photo of their boarding pass on their flight record
    # (client request, Nov 2026). Only possible once staff have recorded the
    # flight. The type is sniffed from the content, not taken from the client,
    # the file gets a neutral name, and a new photo replaces the previous one.
    # Uploading doesn't move the candidate's stage: staff still confirm
    # mobilization themselves. Only accepted inside the upload window, from 2
    # days before the flight's day to 2 days after (CandidateFlightDetail).
    class BoardingPassUploadService < ApplicationService
      ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_BOARDING_PASS_MAX_BYTES', 10.megabytes).to_i
      FIELD = 'boarding_pass.photo'

      def initialize(candidate:, uploaded_file:, request_id:)
        @candidate = candidate
        @uploaded_file = uploaded_file
        @request_id = request_id
      end

      def call
        detail = flight_detail
        validate_upload_window!(detail)
        validate_upload!
        content_type = detected_content_type

        CandidateFlightDetail.transaction do
          detail.boarding_pass.attach(io: rewound_tempfile, filename: filename_for(content_type), content_type:)
          detail.update!(boarding_pass_uploaded_at: Time.current)
          create_audit_event!(detail)
        end

        detail
      end

      private

      def flight_detail
        @candidate.current_assignment&.candidate_flight_detail || raise(NotFoundError)
      end

      def validate_upload_window!(detail)
        state = detail.boarding_pass_upload_state
        opens_on = detail.boarding_pass_upload_opens_on
        raise BoardingPassUploadNotOpenError.new(opens_on:) if state == 'not_yet_open'
        raise BoardingPassUploadClosedError if state == 'closed'
      end

      def validate_upload!
        raise MissingFileError.new(field: FIELD) if @uploaded_file.blank? || !@uploaded_file.respond_to?(:tempfile)
        raise EmptyFileError.new(field: FIELD) if @uploaded_file.size.to_i.zero?
        raise FileTooLargeError.new(field: FIELD) if @uploaded_file.size.to_i > MAX_FILE_BYTES
      end

      def detected_content_type
        content_type = ::Candidates::Documents::UploadedFileInspector.call(uploaded_file: @uploaded_file).content_type
        return content_type if ALLOWED_CONTENT_TYPES.include?(content_type)

        raise UnsupportedFileTypeError.new(field: FIELD, message: I18n.t('api.errors.unsupported_photo_type'))
      end

      def rewound_tempfile
        @uploaded_file.tempfile.tap(&:rewind)
      end

      def filename_for(content_type)
        "boarding-pass.#{content_type.split('/').last.sub('jpeg', 'jpg')}"
      end

      def create_audit_event!(detail)
        AuditEvent.create!(
          actor: nil, candidate: @candidate, candidate_assignment: detail.candidate_assignment,
          entity_type: 'CandidateFlightDetail', entity_id: detail.id,
          action_code: 'candidate_boarding_pass_uploaded', request_id: @request_id,
          metadata: audit_metadata(detail), occurred_at: Time.current
        )
      end

      def audit_metadata(detail)
        {
          candidate_public_id: @candidate.public_id,
          candidate_assignment_public_id: detail.candidate_assignment.public_id,
          flight_detail_public_id: detail.public_id
        }
      end
    end
  end
end
