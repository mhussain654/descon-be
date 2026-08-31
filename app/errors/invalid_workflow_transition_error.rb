# frozen_string_literal: true

class InvalidWorkflowTransitionError < BaseError
  def initialize(message: nil, field: nil, details: nil)
    message ||= I18n.t('api.errors.invalid_workflow_transition')
    super(code: 'invalid_workflow_transition', message:, status: :unprocessable_content, field:, details:)
  end
end
