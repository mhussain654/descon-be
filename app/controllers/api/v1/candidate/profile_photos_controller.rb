# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate set, replace or remove their own profile photo. Always
      # acts on the authenticated candidate -- there is no id in the route, so
      # one candidate can never touch another's photo.
      class ProfilePhotosController < ProtectedController
        def update
          authorize current_candidate, :update_photo?, policy_class: ::Candidates::ProfilePolicy

          ::Candidates::ProfilePhotos::UpdateService.call(
            candidate: current_candidate,
            uploaded_file: params.dig(:profile_photo, :photo),
            request_id: request.request_id
          )
          render_photo
        end

        def destroy
          authorize current_candidate, :destroy_photo?, policy_class: ::Candidates::ProfilePolicy

          ::Candidates::ProfilePhotos::RemoveService.call(candidate: current_candidate, request_id: request.request_id)
          render_photo
        end

        private

        def render_photo
          response.set_header('Cache-Control', 'private, no-store')
          photo_url = ::Candidates::ProfilePhotos::UrlBuilder.call(candidate: current_candidate.reload)
          render_success(data: { photo_url: })
        end
      end
    end
  end
end
