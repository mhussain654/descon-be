# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Auth Sessions', type: :request do
  let!(:admin_user) { create(:user, role: 'admin', email: 'base-admin@example.com', password: 'Password123!') }

  around do |example|
    original_cache = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.store.clear
    AuthenticationEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
    admin_user
    example.run
  ensure
    Rack::Attack.cache.store = original_cache
  end

  def login(email:, password:, headers: {})
    post '/api/v1/auth/login', params: { auth: { email:, password: } }, headers:
  end

  def refresh(refresh_token:, headers: {})
    post '/api/v1/auth/refresh', params: { auth: { refresh_token: } }, headers:
  end

  def logout(access_token:, headers: {})
    delete '/api/v1/auth/logout', headers: headers.merge('Authorization' => "Bearer #{access_token}")
  end

  describe 'POST /api/v1/auth/login' do
    it 'logs in every supported staff role' do
      %w[admin hr mps finance management].each do |role|
        user = create(:user, role:, email: "#{role}-staff@example.com", password: 'Password123!')

        login(email: user.email, password: 'Password123!')

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig('data', 'user', 'role')).to eq(role)
        expect(response.parsed_body.dig('data', 'message')).to eq(I18n.t('api.authentication.login_succeeded'))
      end
    end

    it 'returns an access token and refresh token' do
      login(email: admin_user.email, password: 'Password123!')

      expect(response).to have_http_status(:created)

      body = response.parsed_body
      expect(body.dig('data', 'access_token')).to be_present
      expect(body.dig('data', 'refresh_token')).to be_present
      expect(body.dig('data', 'user', 'email')).to eq(admin_user.email)
      expect(body.dig('data', 'session', 'id')).to be_present
    end

    it 'returns a generic unauthorized error for an unknown email' do
      login(email: 'missing@example.com', password: 'Password123!')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
    end

    it 'returns the identical generic unauthorized error for a bad password' do
      login(email: admin_user.email, password: 'wrong-password')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
    end

    it 'rejects inactive staff accounts' do
      inactive_user = create(:user, active: false, email: 'inactive@example.com', password: 'Password123!')

      login(email: inactive_user.email, password: 'Password123!')

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
    end

    it 'localizes inactive-account responses to Urdu' do
      inactive_user = create(:user, active: false, email: 'inactive-ur@example.com', password: 'Password123!')

      login(email: inactive_user.email, password: 'Password123!', headers: { 'X-Locale' => 'ur' })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.inactive_account', locale: :ur))
    end

    it 'records a successful login audit event' do
      login(email: admin_user.email, password: 'Password123!')

      event = AuthenticationEvent.order(:created_at).last
      expect(event.event_code).to eq('login_succeeded')
      expect(event.user).to eq(admin_user)
      expect(event.session).to be_present
    end

    it 'records a masked failed-login event' do
      login(email: 'missing@example.com', password: 'Password123!')

      event = AuthenticationEvent.order(:created_at).last
      expect(event.event_code).to eq('login_failed')
      expect(event.identifier_masked).to eq('m*****g@example.com')
    end

    it 'returns bad_request when parameters are missing' do
      post '/api/v1/auth/login', params: {}

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('auth')
    end

    it 'rate-limits repeated login attempts by email' do
      (ENV.fetch('AUTH_IDENTITY_RATE_LIMIT_PER_MINUTE', 10).to_i + 1).times do
        login(email: admin_user.email, password: 'wrong-password')
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('rate_limited')
    end

    it 'returns a localized Urdu rate-limit message' do
      (ENV.fetch('AUTH_IDENTITY_RATE_LIMIT_PER_MINUTE', 10).to_i + 1).times do
        login(email: admin_user.email, password: 'wrong-password', headers: { 'X-Locale' => 'ur' })
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.rate_limited', locale: :ur))
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let(:login_response) do
      login(email: admin_user.email, password: 'Password123!')
      response.parsed_body.fetch('data')
    end

    it 'rotates the refresh token' do
      refresh(refresh_token: login_response.fetch('refresh_token'))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'refresh_token')).to be_present
      expect(response.parsed_body.dig('data', 'refresh_token')).not_to eq(login_response.fetch('refresh_token'))
      expect(response.parsed_body.dig('data', 'message')).to eq(I18n.t('api.authentication.refresh_succeeded'))
    end

    it 'returns correct JWT claims' do
      access_token = login_response.fetch('access_token')
      decoded = Authentication::TokenDecoder.call(token: access_token)

      expect(decoded['iss']).to eq(ENV.fetch('JWT_ISSUER', 'descon_backend'))
      expect(decoded['aud']).to eq(ENV.fetch('JWT_AUDIENCE', 'rails_api_clients'))
      expect(decoded['sub']).to eq(admin_user.id.to_s)
      expect(decoded['jti']).to eq(Session.last.jti)
      expect(decoded['exp']).to be > decoded['iat']
    end

    it 'rejects an expired refresh token' do
      raw_token = login_response.fetch('refresh_token')
      RefreshToken.last.update!(expires_at: 1.minute.ago)

      refresh(refresh_token: raw_token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_refresh_token')
    end

    it 'rejects a revoked session during refresh' do
      raw_token = login_response.fetch('refresh_token')
      Session.last.revoke!

      refresh(refresh_token: raw_token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('session_revoked')
    end

    it 'rejects refresh for an inactive account and revokes the session' do
      raw_token = login_response.fetch('refresh_token')
      session = Session.last
      admin_user.update!(active: false)

      refresh(refresh_token: raw_token)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
      expect(session.reload).to be_revoked
    end

    it 'revokes the session when a rotated token is reused' do
      refresh_token_value = login_response.fetch('refresh_token')
      access_token = login_response.fetch('access_token')

      refresh(refresh_token: refresh_token_value)
      expect(response).to have_http_status(:ok)

      refresh(refresh_token: refresh_token_value)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_refresh_token')

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{access_token}" }
      expect(response).to have_http_status(:unauthorized)
      expect(AuthenticationEvent.where(event_code: 'refresh_token_reuse_detected').count).to eq(1)
    end

    it 'records a refresh audit event' do
      refresh(refresh_token: login_response.fetch('refresh_token'))

      event = AuthenticationEvent.order(:created_at).last
      expect(event.event_code).to eq('refresh_succeeded')
    end

    it 'rate-limits repeated refresh attempts' do
      raw_token = 'repeat-refresh-attempt-token'

      (ENV.fetch('AUTH_REFRESH_TOKEN_RATE_LIMIT_PER_MINUTE', 10).to_i + 1).times do
        refresh(refresh_token: raw_token)
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('rate_limited')
    end
  end

  describe 'DELETE /api/v1/auth/logout' do
    def login!
      login(email: admin_user.email, password: 'Password123!')
      response.parsed_body.fetch('data')
    end

    it 'revokes the current session' do
      tokens = login!

      logout(access_token: tokens.fetch('access_token'))

      expect(response).to have_http_status(:ok)
      expect(Session.last).to be_revoked
      expect(response.parsed_body.dig('data', 'message')).to eq(I18n.t('api.authentication.logout_succeeded'))
    end

    it 'is safe to repeat without a new login' do
      tokens = login!

      logout(access_token: tokens.fetch('access_token'))
      logout(access_token: tokens.fetch('access_token'))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'revoked')).to be(true)
      expect(AuthenticationEvent.where(event_code: 'logout_succeeded').count).to eq(1)
    end

    it 'replays a successful logout when the same idempotency key is retried' do
      tokens = login!
      headers = { 'Idempotency-Key' => 'logout-123' }

      logout(access_token: tokens.fetch('access_token'), headers:)
      first_response = response.parsed_body

      logout(access_token: tokens.fetch('access_token'), headers:)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.fetch('data')).to eq(first_response.fetch('data'))
      expect(IdempotencyKey.count).to eq(1)
    end
  end
end
