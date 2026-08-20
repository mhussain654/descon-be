# frozen_string_literal: true

class ValidationError < BaseError
  def initialize(message: 'The request could not be processed.', field: nil)
    super(code: 'validation_failed', message:, status: :unprocessable_entity, field:)
  end
end
