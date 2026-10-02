# frozen_string_literal: true

module Candidates
  module ProfilePhotos
    # Short-lived, signed proxy path for the candidate's own profile photo
    # (nil when none is set). Embedded in the profile response, which is
    # served `Cache-Control: private, no-store` and refetched whenever the app
    # returns to a screen, so a fresh link is always at hand well before the
    # TTL lapses. Same rails_service_blob_proxy_path mechanism as document
    # access -- never a permanent public URL.
    class UrlBuilder < ApplicationService
      TTL = ENV.fetch('CANDIDATE_PROFILE_PHOTO_URL_TTL_SECONDS', 1.hour.to_i).to_i.seconds

      def initialize(candidate:)
        @candidate = candidate
      end

      def call
        return unless @candidate.profile_photo.attached?

        blob = @candidate.profile_photo.blob
        Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
          blob.signed_id(expires_in: TTL), blob.filename, disposition: 'inline', only_path: true
        )
      end
    end
  end
end
