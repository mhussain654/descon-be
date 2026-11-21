# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Boarding Pass Rejections', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate, status_code: 'flight_details_uploaded') }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let!(:detail) do
    flight_day = Time.find_zone!('Asia/Karachi').local(2026, 11, 20, 2, 0)
    create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: flight_day,
                                     boarding_pass_uploaded_at: flight_day - 3.hours,
                                     boarding_pass_check: 'needs_review')
      .tap do |record|
        record.boarding_pass.attach(io: StringIO.new('photo'), filename: 'boarding-pass.jpg',
                                    content_type: 'image/jpeg')
      end
  end
  let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail/boarding_pass_rejection" }
  let(:reason) { 'This is a ticket, not a boarding pass. Please upload the boarding pass from check-in.' }

  def staff_headers(role: 'hr')
    user = create(:user, role:)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def reject(headers: staff_headers, with_reason: reason)
    post path, params: { boarding_pass_rejection: { reason: with_reason } }, headers:
  end

  def candidate_headers
    candidate_session = create(:candidate_session, candidate:)
    { 'Authorization' => "Bearer #{CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)}" }
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/flight_detail/boarding_pass_rejection' do
    it 'rejects it with the reason, audits it, texts the candidate and shows the candidate why' do
      travel_to(Time.find_zone!('Asia/Karachi').local(2026, 11, 22, 10, 0)) do
        reject

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig('data', 'boarding_pass_rejection'))
          .to eq('rejected_at' => Time.current.utc.iso8601, 'reason' => reason)
        expect(response.parsed_body.dig('data', 'boarding_pass_check', 'result')).to eq('needs_review')
        expect(detail.reload).to be_boarding_pass_rejected
        expect(detail.boarding_pass).to be_attached
        expect(AuditEvent.find_by(candidate:, action_code: 'candidate_boarding_pass_rejected')).to be_present
        sms = CandidateSmsDelivery.find_by!(candidate:, message_code: 'document_rejected')
        expect(sms.variables).to include('document' => 'Boarding pass')

        get '/api/v1/candidate/flight_detail', headers: candidate_headers
        expect(response.parsed_body.dig('data', 'boarding_pass_rejection', 'reason')).to eq(reason)
        expect(response.parsed_body['data']).not_to have_key('boarding_pass_check')
        # The normal window closed on 22 Nov; the rejection keeps it open 2 more days.
        expect(response.parsed_body.dig('data', 'boarding_pass_upload'))
          .to include('closes_on' => '2026-11-24', 'state' => 'open')
      end
    end

    it 'lets the candidate upload a new one after the normal window, which clears the rejection' do
      travel_to(Time.find_zone!('Asia/Karachi').local(2026, 11, 23, 10, 0)) do
        reject
        put '/api/v1/candidate/flight_detail/boarding_pass',
            params: { boarding_pass: { photo: fixture_upload('test.jpg', 'image/jpeg') } }, headers: candidate_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('data', 'boarding_pass_rejection')).to be_nil
        expect(detail.reload).to have_attributes(boarding_pass_rejected_at: nil, boarding_pass_check: 'pending')
      end
    end

    it 'requires a reason of at most 500 characters' do
      reject(with_reason: '  ')
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('boarding_pass_rejection.reason')

      reject(with_reason: 'x' * 501)
      expect(response).to have_http_status(:unprocessable_content)
      expect(detail.reload).not_to be_boarding_pass_rejected
    end

    it 'refuses when there is no boarding pass, or it is already rejected' do
      headers = staff_headers
      reject(headers:)
      reject(headers:)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('boarding_pass_already_rejected')

      detail.boarding_pass.purge
      detail.update!(boarding_pass_uploaded_at: nil, boarding_pass_rejected_at: nil, boarding_pass_rejected_by: nil,
                     boarding_pass_rejection_reason: nil)
      reject(headers:)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('boarding_pass_not_uploaded')
    end

    it 'is refused to staff who neither review documents nor manage the workflow' do
      reject(headers: staff_headers(role: 'management'))

      expect(response).to have_http_status(:forbidden)
      expect(detail.reload).not_to be_boarding_pass_rejected
    end

    it 'requires a staff session' do
      post path, params: { boarding_pass_rejection: { reason: } }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
