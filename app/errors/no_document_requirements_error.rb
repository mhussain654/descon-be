# frozen_string_literal: true

class NoDocumentRequirementsError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.no_document_requirements')
    super(code: 'no_document_requirements', message:, status: :unprocessable_entity)
  end
end
