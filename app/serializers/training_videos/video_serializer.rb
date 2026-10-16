# frozen_string_literal: true

module TrainingVideos
  class VideoSerializer
    # Players re-request byte ranges with the same signed URL while seeking, re-buffering or resuming
    # after a pause, so it must outlive a whole viewing session (the files are large); 5 minutes
    # stalled playback mid-video. Links are only issued to authenticated candidates and staff, and
    # only for published videos on the candidate side.
    PLAYBACK_URL_TTL = 1.hour

    def initialize(video, include_access: false)
      @video = video
      @include_access = include_access
    end

    def as_json(*)
      data = attributes
      data[:playback_url] = playback_url if @include_access
      data
    end

    private

    def attributes
      { id: @video.id, title_en: @video.title_en, title_ur: @video.title_ur,
        description_en: @video.description_en, description_ur: @video.description_ur,
        position: @video.position, published: @video.published,
        content_type: @video.file.blob.content_type, byte_size: @video.file.blob.byte_size }
    end

    # The signed S3 URL is issued only to authorized viewers and expires after PLAYBACK_URL_TTL.
    def playback_url
      @video.file.blob.url(expires_in: PLAYBACK_URL_TTL, disposition: :inline)
    end
  end
end
