# frozen_string_literal: true

class DocumentAlreadyReviewedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.document_already_reviewed')
    super(code: 'document_already_reviewed', message:, status: :unprocessable_entity)
  end
end
