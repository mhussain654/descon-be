# frozen_string_literal: true

class ForbiddenError < BaseError
  def initialize(message: 'You are not allowed to perform this action.')
    super(code: 'forbidden', message:, status: :forbidden)
  end
end
