# frozen_string_literal: true

class EmptyFileError < BaseError
  def initialize
    super(
      code: 'empty_file',
      message: I18n.t('api.errors.empty_file'),
      status: :unprocessable_entity,
      field: 'candidate_document.file'
    )
  end
end
