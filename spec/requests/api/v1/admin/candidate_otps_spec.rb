# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate OTPs', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:developer) { create(:user, role: 'developer') }
  let(:candidate) { create(:candidate, preferred_locale: 'ur', mobile_number: '+923001234567') }
  let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/otps" }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  def send_otp(locale, user: developer)
    post path, params: { otp: { locale: } }.to_json, headers: headers_for(user)
  end

  def data = response.parsed_body.fetch('data')

  describe 'access' do
    it 'is forbidden to every role but developer' do
      %w[admin hr mps finance management].each do |role|
        user = create(:user, role:)

        get path, headers: headers_for(user)
        expect(response).to have_http_status(:forbidden), role

        send_otp('en', user:)
        expect(response).to have_http_status(:forbidden), role
      end
      expect(CandidateOtpChallenge.count).to eq(0)
    end

    it 'requires a staff login' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/otps' do
    it "lists the codes sent, newest first, with the candidate's language and sender, never a code" do
      CandidateOtpChallenge.generate_for(candidate:).fetch(:challenge).update!(created_at: 1.hour.ago,
                                                                               expires_at: 50.minutes.ago)
      CandidateOtpChallenge.generate_for(candidate:, sent_by: developer)

      get path, headers: headers_for(developer)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(data).to include('default_locale' => 'ur', 'sender_name' => 'DESCON MPS')
      expect(data['otps'].pluck('status')).to eq(%w[pending expired])
      expect(data['otps'].first['sent_by']).to eq('id' => developer.public_id, 'role' => 'developer')
      expect(data['otps'].last['sent_by']).to be_nil
      expect(data['otps'].flat_map(&:keys)).not_to include('code', 'code_digest')
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/otps' do
    it 'sends a new code in the chosen language, from the candidate sender, and returns it once' do
      candidate.update!(sms_sender: 'short_code')
      allow(Sms::SendMessage).to receive(:call).and_return(Sms::DeliveryResult.new(success: true))

      send_otp('ur')

      expect(response).to have_http_status(:created)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(data['code']).to match(/\A\d{6}\z/)
      expect(data).to include('status' => 'pending', 'sms_sent' => true, 'sms_error_code' => nil)
      expect(Sms::SendMessage).to have_received(:call).with(
        hash_including(to: '+923001234567', template: :otp, locale: 'ur', sender: 'short_code',
                       variables: hash_including(code: data['code']))
      )
      challenge = CandidateOtpChallenge.last
      expect(challenge).to have_attributes(candidate:, sent_by: developer, requested_ip: nil)
      expect(challenge.match?(data['code'])).to be(true)
      expect(AuditEvent.last).to have_attributes(action_code: 'candidate_otp_sent_by_staff', actor: developer)
      expect(AuditEvent.last.metadata.values.map(&:to_s)).not_to include(data['code'])
    end

    it 'sends even inside the app resend cooldown, and the new code replaces the old one' do
      CandidateOtpChallenge.generate_for(candidate:)
      allow(Sms::SendMessage).to receive(:call).and_return(Sms::DeliveryResult.new(success: true))

      send_otp('en')

      expect(response).to have_http_status(:created)
      latest = CandidateOtpChallenge.where(cnic: candidate.cnic).order(created_at: :desc).first
      expect(latest.match?(data['code'])).to be(true)
    end

    it 'still returns the code when the SMS fails, saying so' do
      allow(Sms::SendMessage).to receive(:call).and_return(Sms::DeliveryResult.new(success: false,
                                                                                   error_code: 'invalid_recipient'))

      send_otp('en')

      expect(response).to have_http_status(:created)
      expect(data).to include('sms_sent' => false, 'sms_error_code' => 'invalid_recipient')
      expect(data['code']).to match(/\A\d{6}\z/)
    end

    it 'still returns the code when the SMS provider raises' do
      allow(Sms::SendMessage).to receive(:call).and_raise(Sms::ProviderNotConfiguredError, 'no provider')

      send_otp('en')

      expect(response).to have_http_status(:created)
      expect(data).to include('sms_sent' => false, 'sms_error_code' => 'delivery_error')
    end

    it 'rejects a language other than English or Urdu' do
      send_otp('fr')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('otp.locale')
      expect(CandidateOtpChallenge.count).to eq(0)
    end

    it 'rejects an inactive candidate' do
      candidate.update!(active: false)

      send_otp('en')

      expect(response).to have_http_status(:unprocessable_content)
      expect(CandidateOtpChallenge.count).to eq(0)
    end

    it 'rejects the store review account, which uses its fixed code' do
      allow(StoreReview::Account).to receive(:candidate?).and_return(true)

      send_otp('en')

      expect(response).to have_http_status(:unprocessable_content)
      expect(CandidateOtpChallenge.count).to eq(0)
    end

    it 'returns 404 for an unknown candidate' do
      post '/api/v1/admin/candidates/00000000-0000-0000-0000-000000000000/otps',
           params: { otp: { locale: 'en' } }.to_json, headers: headers_for(developer)

      expect(response).to have_http_status(:not_found)
    end
  end
end
