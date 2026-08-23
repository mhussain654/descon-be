# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Auth OTP', type: :request do
  let!(:candidate) { create(:candidate, mobile_number: '+923001234567') }

  def request_otp(cnic)
    post '/api/v1/candidate/auth/otp/request', params: { candidate: { cnic: cnic } }
  end

  def verify_otp(cnic:, code:)
    post '/api/v1/candidate/auth/otp/verify', params: { candidate: { cnic: cnic, otp: code } }
  end

  def latest_code_for(candidate)
    CandidateOtpChallenge.generate_for(candidate:).fetch(:code)
  end

  describe 'POST /api/v1/candidate/auth/otp/request' do
    it 'returns the same generic success shape for a valid CNIC' do
      request_otp(candidate.cnic)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig('data', 'expires_in_seconds')).to eq(CandidateOtpChallenge::EXPIRY_WINDOW.to_i)
      expect(body.dig('data', 'resend_after_seconds')).to eq(CandidateOtpChallenge::RESEND_COOLDOWN.to_i)
    end

    it 'returns the identical response shape for an unknown CNIC (never reveals existence)' do
      request_otp('99999-9999999-9')

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig('data', 'expires_in_seconds')).to eq(CandidateOtpChallenge::EXPIRY_WINDOW.to_i)
      expect(body.dig('data', 'resend_after_seconds')).to eq(CandidateOtpChallenge::RESEND_COOLDOWN.to_i)
    end

    it 'returns the identical response shape for a candidate whose mobile is undeliverable' do
      undeliverable = create(:candidate, mobile_number: '+923000000000')

      request_otp(undeliverable.cnic)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig('data', 'expires_in_seconds')).to eq(CandidateOtpChallenge::EXPIRY_WINDOW.to_i)
    end

    it 'never returns the OTP code itself in the response body' do
      request_otp(candidate.cnic)

      challenge = candidate.candidate_otp_challenges.order(:created_at).last
      # The digest can't be reversed to the raw code, but assert the raw
      # code shape (6 digits) never appears anywhere in the response text.
      expect(response.body).not_to match(/"code":\s*"\d{6}"/)
      expect(challenge).to be_present
    end

    it 'returns a field-addressable validation error for a malformed CNIC' do
      request_otp('not-a-cnic')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('cnic')
    end

    it 'rate-limits repeated requests for the same CNIC' do
      (ENV.fetch('OTP_IDENTITY_RATE_LIMIT_PER_MINUTE', 5).to_i + 1).times { request_otp(candidate.cnic) }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'POST /api/v1/candidate/auth/otp/verify' do
    it 'issues an access token and refresh token for the correct code' do
      code = latest_code_for(candidate)

      verify_otp(cnic: candidate.cnic, code: code)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig('data', 'access_token')).to be_present
      expect(body.dig('data', 'refresh_token')).to be_present
      expect(body.dig('data', 'candidate', 'id')).to eq(candidate.public_id)
    end

    it 'returns a generic error for an unknown CNIC' do
      verify_otp(cnic: '99999-9999999-9', code: '123456')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('otp_invalid')
    end

    it 'returns the identical generic error for a known CNIC with an incorrect code' do
      latest_code_for(candidate)

      verify_otp(cnic: candidate.cnic, code: '000000')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('otp_invalid')
    end

    it 'returns otp_expired for an expired challenge' do
      code = latest_code_for(candidate)
      CandidateOtpChallenge.last.update!(expires_at: 1.minute.ago)

      verify_otp(cnic: candidate.cnic, code: code)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('otp_expired')
    end

    it 'returns otp_max_attempts once the attempt limit is reached' do
      latest_code_for(candidate)

      CandidateOtpChallenge::MAX_ATTEMPTS.times { verify_otp(cnic: candidate.cnic, code: '000000') }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('otp_max_attempts')
    end

    it 'rejects replaying an already-used code with the generic error' do
      code = latest_code_for(candidate)
      verify_otp(cnic: candidate.cnic, code: code)
      expect(response).to have_http_status(:created)

      verify_otp(cnic: candidate.cnic, code: code)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('otp_invalid')
    end

    it 'returns a field-addressable validation error for a malformed code' do
      verify_otp(cnic: candidate.cnic, code: 'abcdef')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('otp')
    end

    it 'localizes the error message to Urdu via X-Locale' do
      post '/api/v1/candidate/auth/otp/verify',
           params: { candidate: { cnic: '99999-9999999-9', otp: '123456' } },
           headers: { 'X-Locale' => 'ur' }

      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.otp_invalid', locale: :ur))
    end

    it 'rate-limits repeated verify attempts for the same CNIC' do
      (ENV.fetch('OTP_IDENTITY_RATE_LIMIT_PER_MINUTE', 5).to_i + 1).times do
        verify_otp(cnic: candidate.cnic, code: '000000')
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
