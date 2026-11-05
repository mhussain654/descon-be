# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Verifies a candidate's current bank details.
      class CandidateBankDetailVerificationsController < ProtectedStaffController
        include CandidateBankDetailReview

        def create
          review!(decision: 'verified', scope: 'admin.candidate_bank_details.verifications.create')
        end
      end
    end
  end
end
