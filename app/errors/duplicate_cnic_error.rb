# frozen_string_literal: true

class DuplicateCnicError < BaseError
  def initialize
    super(
      code: 'duplicate_cnic',
      message: I18n.t('api.errors.duplicate_cnic'),
      status: :unprocessable_content,
      field: 'cnic'
    )
  end
end
