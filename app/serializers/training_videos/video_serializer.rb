# frozen_string_literal: true

module TrainingVideos
  class VideoSerializer
    def initialize(video, include_access: false)
      @video = video
      @include_access = include_access
    end

    def as_json(*)
      data = { id: @video.id, title_en: @video.title_en, title_ur: @video.title_ur,
               description_en: @video.description_en, description_ur: @video.description_ur,
               position: @video.position, published: @video.published,
               content_type: @video.file.blob.content_type,
               byte_size: @video.file.blob.byte_size }
      # The signed S3 URL expires quickly and is issued only to authorized viewers.
      data[:playback_url] = @video.file.blob.url(expires_in: 5.minutes, disposition: :inline) if @include_access
      data
    end
  end
end
