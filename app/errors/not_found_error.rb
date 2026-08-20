# frozen_string_literal: true

class NotFoundError < BaseError
  def initialize(message: 'Record not found.')
    super(code: 'not_found', message:, status: :not_found)
  end
end
