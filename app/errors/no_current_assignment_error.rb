# frozen_string_literal: true

class NoCurrentAssignmentError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.no_current_assignment')
    super(code: 'no_current_assignment', message:, status: :unprocessable_content)
  end
end
