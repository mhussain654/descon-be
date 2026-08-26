# frozen_string_literal: true

class FileTooLargeError < BaseError
  def initialize
    super(
      code: 'file_too_large',
      message: I18n.t('api.errors.file_too_large'),
      status: :unprocessable_entity,
      field: 'candidate_document.file'
    )
  end
end
