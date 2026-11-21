# frozen_string_literal: true

# Staff tried to reject a boarding pass that is already rejected; the candidate
# has to upload a new one first.
class BoardingPassAlreadyRejectedError < BaseError
  def initialize
    super(code: 'boarding_pass_already_rejected', message: I18n.t('api.errors.boarding_pass_already_rejected'),
          status: :conflict)
  end
end
