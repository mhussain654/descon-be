# frozen_string_literal: true

class WorkflowTransitionPrerequisiteError < BaseError
  def initialize(message: nil, field: nil, details: nil)
    message ||= I18n.t('api.errors.workflow_transition_prerequisite_missing')
    super(code: 'workflow_transition_prerequisite_missing', message:, status: :unprocessable_content, field:, details:)
  end
end
