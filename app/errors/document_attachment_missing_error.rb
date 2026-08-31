# frozen_string_literal: true

class DocumentAttachmentMissingError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.document_attachment_missing')
    super(code: 'document_attachment_missing', message:, status: :unprocessable_content)
  end
end
