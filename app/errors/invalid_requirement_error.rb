# frozen_string_literal: true

class InvalidRequirementError < BaseError
  def initialize
    super(
      code: 'invalid_requirement',
      message: I18n.t('api.errors.invalid_requirement'),
      status: :unprocessable_entity,
      field: 'candidate_document.requirement_code'
    )
  end
end
