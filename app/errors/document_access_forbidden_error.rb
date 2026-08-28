# frozen_string_literal: true

class DocumentAccessForbiddenError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.document_access_forbidden')
    super(code: 'document_access_forbidden', message:, status: :forbidden)
  end
end
