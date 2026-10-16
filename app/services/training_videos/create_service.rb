# frozen_string_literal: true

module TrainingVideos
  # Registers a training video from a file the staff member already uploaded straight to storage.
  # Nothing in the request is trusted: the blob must be this user's own, recent, unclaimed, declared
  # as an MP4 within the size limit, actually present in storage, and really start like an MP4.
  class CreateService < ApplicationService
    CONTENT_TYPE = DirectUploadTicketService::CONTENT_TYPE
    REGISTRATION_WINDOW = DirectUploadTicketService::REGISTRATION_WINDOW
    MP4_SIGNATURE = 'ftyp'

    def initialize(creator:, attributes:, signed_blob_id:)
      @creator = creator
      @attributes = attributes
      @signed_blob_id = signed_blob_id
    end

    def call
      blob = verified_blob
      TrainingVideo.new(@attributes.merge(created_by: @creator)).tap do |video|
        video.file.attach(blob)
        video.save!
      end
    end

    private

    def verified_blob
      blob = ActiveStorage::Blob.find_signed(@signed_blob_id)
      raise InvalidFileError unless blob && acceptable?(blob)

      blob
    end

    def acceptable?(blob)
      uploaded_by_creator?(blob) && still_unclaimed?(blob) && declared_as_mp4?(blob) && stored_as_mp4?(blob)
    end

    def uploaded_by_creator?(blob)
      blob.metadata['training_video_owner_id'].to_s == @creator.id.to_s
    end

    def still_unclaimed?(blob)
      blob.created_at > REGISTRATION_WINDOW.ago && !blob.attachments.exists?
    end

    def declared_as_mp4?(blob)
      blob.content_type == CONTENT_TYPE && blob.byte_size.between?(1, TrainingVideo::MAX_BYTES)
    end

    def stored_as_mp4?(blob)
      blob.service.exist?(blob.key) && blob.download_chunk(0..11).byteslice(4, 4) == MP4_SIGNATURE
    end
  end
end
