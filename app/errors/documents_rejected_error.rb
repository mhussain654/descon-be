# frozen_string_literal: true

class DocumentsRejectedError < BaseError
  def initialize(message: nil, blocking_requirements: [])
    message ||= I18n.t('api.errors.documents_rejected')
    super(
      code: 'documents_rejected',
      message:,
      status: :unprocessable_entity,
      details: { blocking_requirements: }
    )
  end
end
