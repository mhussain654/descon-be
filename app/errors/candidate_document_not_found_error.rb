# frozen_string_literal: true

class CandidateDocumentNotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.candidate_document_not_found')
    super(code: 'candidate_document_not_found', message:, status: :not_found)
  end
end
