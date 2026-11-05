# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Rejects a candidate's current bank details, with a reason they see.
      class CandidateBankDetailRejectionsController < ProtectedStaffController
        include CandidateBankDetailReview

        def create
          review!(decision: 'rejected', scope: 'admin.candidate_bank_details.rejections.create',
                  rejection_reason: params.expect(rejection: %i[reason])[:reason])
        end
      end
    end
  end
end
