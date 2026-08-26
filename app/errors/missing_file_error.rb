# frozen_string_literal: true

class MissingFileError < BaseError
  def initialize
    super(
      code: 'missing_file',
      message: I18n.t('api.errors.missing_file'),
      status: :unprocessable_entity,
      field: 'candidate_document.file'
    )
  end
end
