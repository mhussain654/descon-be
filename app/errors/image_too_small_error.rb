# frozen_string_literal: true

# A document photo below Candidates::Documents::ImageDimensions::MINIMUM_SIDE
# on either side: too small to read, so it is refused before it is stored.
class ImageTooSmallError < BaseError
  def initialize(field: 'candidate_document.file')
    super(
      code: 'image_too_small',
      message: I18n.t('api.errors.image_too_small', minimum: Candidates::Documents::ImageDimensions::MINIMUM_SIDE),
      status: :unprocessable_content,
      field:
    )
  end
end
