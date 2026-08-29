# frozen_string_literal: true

class WorkflowTransitionStaleError < BaseError
  def initialize(message: nil, field: nil, details: nil)
    message ||= I18n.t('api.errors.workflow_transition_stale')
    super(code: 'workflow_transition_stale', message:, status: :conflict, field:, details:)
  end
end
