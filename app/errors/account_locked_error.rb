# frozen_string_literal: true

class AccountLockedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.account_locked')
    super(code: 'account_locked', message:, status: :locked)
  end
end
