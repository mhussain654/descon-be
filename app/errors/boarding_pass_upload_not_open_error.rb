# frozen_string_literal: true

# The candidate tried to upload their boarding pass before its upload window opens
# (2 days before the flight's day; see CandidateFlightDetail).
class BoardingPassUploadNotOpenError < BaseError
  def initialize(opens_on:)
    # Day/month/year, the format the candidate app shows everywhere.
    message = I18n.t('api.errors.boarding_pass_upload_not_open', date: opens_on.strftime('%d/%m/%Y'))
    super(code: 'boarding_pass_upload_not_open', message:, status: :unprocessable_content)
  end
end
