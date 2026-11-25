# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Profile', type: :request do
  before do
    ensure_canonical_workflow_stages!
  end

  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  describe 'GET /api/v1/candidate/profile' do
    it 'returns only the authenticated candidate profile with masked sensitive data' do
      candidate = create(:candidate, cnic: '42101-1234567-1', preferred_locale: 'ur', status_code: 'registered')
      create(:candidate_assignment, candidate:, reference_number: 'DES-000111')

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['ETag']).to be_present
      expect(response.parsed_body.dig('data', 'id')).to eq(candidate.public_id)
      expect(response.parsed_body.dig('data', 'masked_cnic')).to eq('42101-*******-1')
      expect(response.parsed_body.dig('data', 'reference_number')).to eq('DES-000111')
      expect(response.parsed_body.dig('data', 'candidate_status')).to eq('registered')
      expect(response.parsed_body.dig('data', 'current_workflow_stage', 'code')).to eq('registered')
      expect(response.parsed_body.dig('data', 'payment', 'required_stage_code')).to eq('fee_pending')
      expect(response.parsed_body.dig('data', 'payment', 'blocking_reasons')).to eq(['payment_stage_not_reached'])
      expect(response.parsed_body.dig('data', 'consent', 'accepted')).to be(true)
      expect(response.parsed_body.dig('data', 'consent', 'current_policy_version'))
        .to eq(CandidateConsent::CURRENT_POLICY_VERSION)
      expect(response.body).not_to include(candidate.cnic)
      expect(response.body).not_to include(candidate.mobile_number)
    end

    it 'returns the assignment country (the Business Unit) with a localized name, and no photo by default' do
      candidate = create(:candidate)
      country = create(:country, name_en: 'Qatar', name_ur: 'قطر')
      create(:candidate_assignment, candidate:, country:)

      get '/api/v1/candidate/profile',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}", 'X-Locale' => 'ur' }

      expect(response.parsed_body.dig('data', 'country')).to eq('code' => country.code, 'name' => 'قطر')
      expect(response.parsed_body.dig('data', 'photo_url')).to be_nil
    end

    it 'returns the assignment craft with a localized name' do
      candidate = create(:candidate)
      craft = create(:craft, name_en: 'Welder', name_ur: 'ویلڈر')
      create(:candidate_assignment, candidate:, craft:)

      get '/api/v1/candidate/profile',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}", 'X-Locale' => 'ur' }

      expect(response.parsed_body.dig('data', 'craft')).to eq('code' => craft.code, 'name' => 'ویلڈر')
    end

    it 'returns no craft before the candidate has an assignment' do
      candidate = create(:candidate)

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response.parsed_body.dig('data', 'craft')).to be_nil
    end

    it 'returns a short-lived signed link once the candidate has a photo' do
      candidate = create(:candidate)
      candidate.profile_photo.attach(io: Rails.root.join('spec/fixtures/files/test.jpg').open,
                                     filename: 'profile-photo.jpg', content_type: 'image/jpeg')

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response.parsed_body.dig('data', 'photo_url')).to start_with('/rails/active_storage/blobs/proxy/')
    end

    it 'blocks a candidate who has not accepted the current policy version' do
      candidate = create(:candidate, :without_consent)

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('consent_required')
    end

    it 'rejects missing, invalid, revoked, or expired candidate sessions' do
      candidate = create(:candidate)

      get '/api/v1/candidate/profile'
      expect(response).to have_http_status(:unauthorized)

      get '/api/v1/candidate/profile', headers: { 'Authorization' => 'Bearer invalid.token' }
      expect(response).to have_http_status(:unauthorized)

      token = candidate_access_token_for(candidate)
      CandidateSession.last.revoke!
      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)

      token = candidate_access_token_for(candidate)
      travel_to((CandidateAuthentication::TokenIssuer::ACCESS_TOKEN_TTL + 1.second).from_now) do
        get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{token}" }
      end
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects inactive candidates and staff tokens' do
      candidate = create(:candidate, active: false)
      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
      staff_token = response.parsed_body.dig('data', 'access_token')

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{staff_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns Urdu error messages when requested' do
      get '/api/v1/candidate/profile',
          headers: { 'Authorization' => 'Bearer invalid.token', 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.unauthorized', locale: :ur))
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end

  describe 'PATCH /api/v1/candidate/profile' do
    let(:candidate) { create(:candidate) }
    let(:headers) { { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" } }

    def update_email(email, extra_headers = {})
      patch '/api/v1/candidate/profile', params: { candidate_profile: { email: } },
                                         headers: headers.merge(extra_headers)
    end

    it 'saves the email lowercased, returns it in the profile and records an audit event' do
      update_email('  Candidate@Example.COM ')

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.dig('data', 'email')).to eq('candidate@example.com')
      expect(candidate.reload.email).to eq('candidate@example.com')
      event = AuditEvent.find_by!(action_code: 'candidate_email_updated', candidate:)
      expect(event.metadata).to eq('candidate_public_id' => candidate.public_id, 'email_present' => true)
    end

    it 'shows the saved email in GET /profile' do
      candidate.update!(email: 'saved@example.com')

      get '/api/v1/candidate/profile', headers: headers

      expect(response.parsed_body.dig('data', 'email')).to eq('saved@example.com')
    end

    it 'clears the email when blank is sent' do
      candidate.update!(email: 'old@example.com')

      update_email('')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'email')).to be_nil
      expect(candidate.reload.email).to be_nil
    end

    it 'records no audit event when the email is unchanged' do
      candidate.update!(email: 'same@example.com')

      expect { update_email('SAME@example.com') }.not_to change(AuditEvent, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'refuses an invalid email with a localized message' do
      update_email('not-an-email', 'X-Locale' => 'ur')

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.slice('code', 'field')).to eq('code' => 'invalid_email', 'field' => 'candidate_profile.email')
      expect(error['message']).to eq(I18n.t('api.errors.invalid_email', locale: :ur))
      expect(candidate.reload.email).to be_nil
    end

    it 'refuses an email longer than 254 characters' do
      update_email("#{'a' * 250}@example.com")

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_email')
    end

    it 'requires the candidate_profile parameter' do
      patch '/api/v1/candidate/profile', params: {}, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects an unauthenticated request' do
      patch '/api/v1/candidate/profile', params: { candidate_profile: { email: 'x@example.com' } }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an inactive candidate' do
      candidate.update!(active: false)

      update_email('x@example.com')

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
      expect(candidate.reload.email).to be_nil
    end
  end
end
