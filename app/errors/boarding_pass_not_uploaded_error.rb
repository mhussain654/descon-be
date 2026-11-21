# frozen_string_literal: true

# Staff tried to reject a boarding pass the candidate hasn't uploaded.
class BoardingPassNotUploadedError < BaseError
  def initialize
    super(code: 'boarding_pass_not_uploaded', message: I18n.t('api.errors.boarding_pass_not_uploaded'),
          status: :unprocessable_content)
  end
end
