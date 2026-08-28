# frozen_string_literal: true

class DocumentSubmissionNotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.document_submission_not_found')
    super(code: 'document_submission_not_found', message:, status: :not_found)
  end
end
