# frozen_string_literal: true

class DocumentNotPendingReviewError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.document_not_pending_review')
    super(code: 'document_not_pending_review', message:, status: :unprocessable_entity)
  end
end
