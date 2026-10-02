# frozen_string_literal: true

class MissingFileError < BaseError
  # `field` defaults to the candidate-document upload's form field; other
  # upload endpoints (e.g. the profile photo) pass their own.
  def initialize(field: 'candidate_document.file')
    super(
      code: 'missing_file',
      message: I18n.t('api.errors.missing_file'),
      status: :unprocessable_content,
      field:
    )
  end
end
