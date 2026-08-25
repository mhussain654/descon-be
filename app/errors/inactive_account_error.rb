# frozen_string_literal: true

class InactiveAccountError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.inactive_account')
    super(code: 'inactive_account', message:, status: :forbidden)
  end
end
