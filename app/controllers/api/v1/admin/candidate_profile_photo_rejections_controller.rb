# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Rejects a candidate's profile photo: it is removed and the app asks the
      # candidate for a clear photo of their own face.
      class CandidateProfilePhotoRejectionsController < ProtectedStaffController
        include CandidateProfilePhotoReview

        def create
          review!(decision: 'rejected')
        end
      end
    end
  end
end
