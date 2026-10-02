# frozen_string_literal: true

class UnsupportedFileTypeError < BaseError
  # `field` defaults to the candidate-document upload's form field; other
  # upload endpoints (e.g. the profile photo) pass their own.
  def initialize(field: 'candidate_document.file', message: I18n.t('api.errors.unsupported_file_type'))
    super(
      code: 'unsupported_file_type',
      message:,
      status: :unprocessable_content,
      field:
    )
  end
end
