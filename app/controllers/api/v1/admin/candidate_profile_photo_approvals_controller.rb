# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Approves a candidate's profile photo.
      class CandidateProfilePhotoApprovalsController < ProtectedStaffController
        include CandidateProfilePhotoReview

        def create
          review!(decision: 'approved')
        end
      end
    end
  end
end
