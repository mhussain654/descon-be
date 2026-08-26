# frozen_string_literal: true

class ReplacementNotAllowedError < BaseError
  def initialize
    super(
      code: 'replacement_not_allowed',
      message: I18n.t('api.errors.replacement_not_allowed'),
      status: :unprocessable_entity,
      field: 'candidate_document.requirement_code'
    )
  end
end
