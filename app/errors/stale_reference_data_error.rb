# frozen_string_literal: true

class StaleReferenceDataError < BaseError
  def initialize
    super(
      code: 'stale_reference_data',
      message: I18n.t('api.errors.stale_reference_data'),
      status: :conflict
    )
  end
end
