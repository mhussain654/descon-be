# frozen_string_literal: true

# The candidate tried to upload their boarding pass after its upload window closed
# (2 days after the flight's day; see CandidateFlightDetail).
class BoardingPassUploadClosedError < BaseError
  def initialize
    super(code: 'boarding_pass_upload_closed', message: I18n.t('api.errors.boarding_pass_upload_closed'),
          status: :unprocessable_content)
  end
end
