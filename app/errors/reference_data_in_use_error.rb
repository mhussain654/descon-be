# frozen_string_literal: true

class ReferenceDataInUseError < BaseError
  def initialize
    super(
      code: 'reference_data_in_use',
      message: I18n.t('api.errors.reference_data_in_use'),
      status: :unprocessable_content
    )
  end
end
