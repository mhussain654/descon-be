# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view their own registration/personal profile details.
      class ProfilesController < ProtectedController
        # Returns the current candidate's profile, with cache/ETag headers reflecting the
        # assignment's last update time.
        def show
          profile = ::Candidates::ProfileService.call(candidate: current_candidate)

          authorize profile, policy_class: ::Candidates::ProfilePolicy
          set_private_state_headers(
            updated_at: profile.current_assignment&.updated_at,
            etag_key: profile_etag_key(profile)
          )
          render_success(data: ::Candidates::ProfileSerializer.new(profile).as_json)
        end

        private

        # Changes when the photo, or staff's decision on it, changes.
        def profile_etag_key(profile)
          photo = [profile.profile_photo.attachment&.blob_id, profile.profile_photo_status,
                   profile.profile_photo_reviewed_at&.to_i]
          "#{profile.public_id}:profile:#{photo.join(':')}"
        end
      end
    end
  end
end
