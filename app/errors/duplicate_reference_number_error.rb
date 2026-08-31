# frozen_string_literal: true

class DuplicateReferenceNumberError < BaseError
  def initialize
    super(
      code: 'duplicate_reference_number',
      message: I18n.t('api.errors.duplicate_reference_number'),
      status: :unprocessable_content,
      field: 'reference_number'
    )
  end
end
