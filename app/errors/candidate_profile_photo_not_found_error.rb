# frozen_string_literal: true

class CandidateProfilePhotoNotFoundError < BaseError
  def initialize
    super(
      code: 'candidate_profile_photo_not_found',
      message: I18n.t('api.errors.candidate_profile_photo_not_found'),
      status: :not_found
    )
  end
end
