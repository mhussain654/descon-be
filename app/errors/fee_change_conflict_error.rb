# frozen_string_literal: true

class FeeChangeConflictError < BaseError
  def initialize(code: 'stale_fee')
    super(code:, message: I18n.t("api.errors.#{code}"), status: :conflict)
  end
end
