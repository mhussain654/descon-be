# frozen_string_literal: true

class UnsupportedFileTypeError < BaseError
  def initialize
    super(
      code: 'unsupported_file_type',
      message: I18n.t('api.errors.unsupported_file_type'),
      status: :unprocessable_content,
      field: 'candidate_document.file'
    )
  end
end
