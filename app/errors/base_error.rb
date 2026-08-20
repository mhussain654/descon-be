# frozen_string_literal: true

class BaseError < StandardError
  attr_reader :code, :field, :status

  def initialize(code:, message:, status:, field: nil)
    super(message)
    @code = code
    @field = field
    @status = status
  end
end
