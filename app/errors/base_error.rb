# frozen_string_literal: true

class BaseError < StandardError
  attr_reader :code, :details, :field, :status

  def initialize(code:, message:, status:, field: nil, details: nil)
    super(message)
    @code = code
    @details = details
    @field = field
    @status = status
  end
end
