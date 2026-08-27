# frozen_string_literal: true

class DocumentsIncompleteError < BaseError
  def initialize(message: nil, blocking_requirements: [])
    message ||= I18n.t('api.errors.documents_incomplete')
    super(
      code: 'documents_incomplete',
      message:,
      status: :unprocessable_entity,
      details: { blocking_requirements: }
    )
  end
end
