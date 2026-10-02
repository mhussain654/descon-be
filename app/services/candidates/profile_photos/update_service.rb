# frozen_string_literal: true

module Candidates
  module ProfilePhotos
    # Sets or replaces the candidate's own profile photo. Validates the real
    # (content-sniffed, not client-declared) type and size the same way
    # Documents::UploadService does, attaches under a fixed filename (the
    # original name is irrelevant and may carry personal text), and records an
    # audit event. Replacing simply re-attaches -- Active Storage purges the
    # previous blob.
    class UpdateService < ApplicationService
      ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_PROFILE_PHOTO_MAX_BYTES', 5.megabytes).to_i
      FIELD = 'profile_photo.photo'

      def initialize(candidate:, uploaded_file:, request_id:)
        @candidate = candidate
        @uploaded_file = uploaded_file
        @request_id = request_id
      end

      def call
        validate_upload!
        content_type = detected_content_type

        ::Candidate.transaction do
          @candidate.profile_photo.attach(io: rewound_tempfile, filename: filename_for(content_type), content_type:)
          create_audit_event!
        end

        @candidate
      end

      private

      def validate_upload!
        raise MissingFileError.new(field: FIELD) if @uploaded_file.blank? || !@uploaded_file.respond_to?(:tempfile)
        raise EmptyFileError.new(field: FIELD) if @uploaded_file.size.to_i.zero?
        raise FileTooLargeError.new(field: FIELD) if @uploaded_file.size.to_i > MAX_FILE_BYTES
      end

      def detected_content_type
        content_type = Documents::UploadedFileInspector.call(uploaded_file: @uploaded_file).content_type
        return content_type if ALLOWED_CONTENT_TYPES.include?(content_type)

        raise UnsupportedFileTypeError.new(field: FIELD, message: I18n.t('api.errors.unsupported_photo_type'))
      end

      def rewound_tempfile
        @uploaded_file.tempfile.tap(&:rewind)
      end

      def filename_for(content_type)
        "profile-photo.#{content_type.split('/').last.sub('jpeg', 'jpg')}"
      end

      def create_audit_event!
        AuditEvent.create!(
          actor: nil, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
          action_code: 'candidate_profile_photo_updated', request_id: @request_id,
          metadata: { candidate_public_id: @candidate.public_id }, occurred_at: Time.current
        )
      end
    end
  end
end
