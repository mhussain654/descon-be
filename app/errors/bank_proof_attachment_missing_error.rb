# frozen_string_literal: true

class BankProofAttachmentMissingError < BaseError
  def initialize
    super(
      code: 'bank_proof_attachment_missing',
      message: I18n.t('api.errors.bank_proof_attachment_missing'),
      status: :unprocessable_entity
    )
  end
end
