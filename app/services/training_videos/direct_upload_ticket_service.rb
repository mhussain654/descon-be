# frozen_string_literal: true

module TrainingVideos
  # Issues the short-lived, size-bounded ticket the browser uses to PUT an MP4 straight to storage.
  # The blob is tagged with its owner so only the staff member who requested the ticket can later
  # register it as a training video (see CreateService).
  class DirectUploadTicketService < ApplicationService
    CONTENT_TYPE = 'video/mp4'
    CHECKSUM_FORMAT = %r{\A[A-Za-z0-9+/]{22}==\z}
    TICKET_TTL = 15.minutes
    REGISTRATION_WINDOW = 2.hours

    def initialize(owner:, filename:, byte_size:, content_type:, checksum:)
      @owner = owner
      @filename = filename
      @byte_size = Integer(byte_size, exception: false)
      @content_type = content_type
      @checksum = checksum.to_s
    end

    def call
      raise InvalidFileError unless acceptable?

      blob = create_blob
      { signed_id: blob.signed_id(expires_in: REGISTRATION_WINDOW),
        upload_url: blob.service_url_for_direct_upload(expires_in: TICKET_TTL),
        upload_headers: blob.service_headers_for_direct_upload }
    end

    private

    def acceptable?
      @filename.present? && @byte_size&.between?(1, TrainingVideo::MAX_BYTES) &&
        @content_type == CONTENT_TYPE && @checksum.match?(CHECKSUM_FORMAT)
    end

    def create_blob
      ActiveStorage::Blob.create_before_direct_upload!(
        filename: @filename, byte_size: @byte_size, checksum: @checksum, content_type: CONTENT_TYPE,
        metadata: { training_video_owner_id: @owner.id }
      )
    end
  end
end
