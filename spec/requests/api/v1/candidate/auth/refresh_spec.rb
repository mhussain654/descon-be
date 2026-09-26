# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Auth Refresh', type: :request do
  let!(:candidate) { create(:candidate, mobile_number: '+923001234567') }
  let(:candidate_session) { create(:candidate_session, candidate:) }
  let!(:refresh_token) { CandidateAuthentication::RefreshTokenIssuer.call(candidate_session:) }

  around do |example|
    original_cache = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original_cache
  end

  def refresh(token)
    post '/api/v1/candidate/auth/refresh', params: { candidate: { refresh_token: token } }
  end

  it 'issues a new access/refresh pair and rotates the presented token' do
    refresh(refresh_token)

    expect(response).to have_http_status(:ok)
    data = response.parsed_body.fetch('data')
    expect(data['refresh_token']).to be_present.and(satisfy { |token| token != refresh_token })
    expect(data['expires_in']).to eq(CandidateAuthentication::TokenIssuer::ACCESS_TOKEN_TTL.to_i)
    expect(data.dig('candidate', 'full_name')).to eq(candidate.full_name)
    claims = CandidateAuthentication::TokenDecoder.call(token: data['access_token'])
    expect(claims.fetch('sub')).to eq(candidate.id.to_s)
  end

  it 'rejects a token that was already rotated and revokes the whole session (reuse detection)' do
    refresh(refresh_token)
    new_token = response.parsed_body.dig('data', 'refresh_token')

    refresh(refresh_token)

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_refresh_token')
    expect(candidate_session.reload).to be_revoked

    refresh(new_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an unknown token' do
    refresh('not-a-real-token')

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_refresh_token')
  end

  it 'rejects an expired token' do
    CandidateRefreshToken.update_all(expires_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations

    refresh(refresh_token)

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_refresh_token')
  end

  it 'rejects a token whose session was revoked' do
    candidate_session.revoke!

    refresh(refresh_token)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses an inactive candidate and revokes the session' do
    candidate.update!(active: false)

    refresh(refresh_token)

    expect(response).to have_http_status(:forbidden)
    expect(candidate_session.reload).to be_revoked
  end

  it 'rejects a malformed body' do
    post '/api/v1/candidate/auth/refresh', params: {}

    expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)
  end

  it 'throttles repeated attempts with the same token' do
    (ENV.fetch('AUTH_REFRESH_TOKEN_RATE_LIMIT_PER_MINUTE', 10).to_i + 1).times { refresh('same-token') }

    expect(response).to have_http_status(:too_many_requests)
  end
end
