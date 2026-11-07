# frozen_string_literal: true

module Admin
  # The candidate's profile photo and its staff review, with a short-lived
  # signed link (null once a photo is rejected and removed).
  class CandidateProfilePhotoSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      {
        status: @candidate.profile_photo_status,
        url: ::Candidates::ProfilePhotos::UrlBuilder.call(candidate: @candidate),
        reviewed_at: @candidate.profile_photo_reviewed_at&.utc&.iso8601
      }
    end
  end
end
