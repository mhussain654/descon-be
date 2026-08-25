# frozen_string_literal: true

class InvalidInvitationError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.invalid_invitation')
    super(code: 'invalid_invitation', message:, status: :unauthorized)
  end
end
