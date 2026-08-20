# frozen_string_literal: true

class UnauthorizedError < BaseError
  def initialize(message: 'Invalid credentials.')
    super(code: 'unauthorized', message:, status: :unauthorized)
  end
end
