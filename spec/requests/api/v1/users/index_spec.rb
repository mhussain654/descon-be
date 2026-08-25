# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Users Index', type: :request do
  let!(:admin) { create(:user, role: 'admin', email: 'admin@example.com', password: 'Password123!') }
  let!(:hr_user) do
    create(
      :user,
      role: 'hr',
      email: 'hr@example.com',
      active: true,
      password: 'Password123!',
      created_at: 2.days.ago
    )
  end
  let!(:mps_user) do
    create(
      :user,
      role: 'mps',
      email: 'mps@example.com',
      active: true,
      password: 'Password123!',
      created_at: Time.current
    )
  end
  let!(:active_finance_user) do
    create(
      :user,
      role: 'finance',
      email: 'finance-active@example.com',
      active: true,
      password: 'Password123!'
    )
  end
  let!(:management_user) do
    create(
      :user,
      role: 'management',
      email: 'management@example.com',
      active: true,
      password: 'Password123!',
      created_at: 3.days.ago
    )
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  before do
    ensure_staff_authorization_reference_data!
    create(
      :user,
      role: 'finance',
      email: 'finance@example.com',
      active: false,
      password: 'Password123!',
      created_at: 1.day.ago
    )
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def user_for_role(role)
    {
      admin: admin,
      hr: hr_user,
      mps: mps_user,
      finance: active_finance_user,
      management: management_user
    }.fetch(role)
  end

  describe 'GET /api/v1/users' do
    it 'returns a paginated collection response with public identifiers for admins' do
      get '/api/v1/users',
          params: { page: { number: 1, size: 2 }, sort: 'email' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').size).to eq(2)
      expect(response.parsed_body.dig('data', 0, 'id')).to be_present
      expect(response.parsed_body.dig('data', 0)).not_to have_key('user_id')
      expect(response.parsed_body.dig('meta', 'pagination')).to eq(
        'page' => 1,
        'per_page' => 2,
        'total_count' => 6,
        'total_pages' => 3
      )
      expect(response.parsed_body.fetch('errors')).to eq([])
    end

    it 'allows the admin role and forbids every other supported staff role' do
      {
        admin: :ok,
        hr: :forbidden,
        mps: :forbidden,
        finance: :forbidden,
        management: :forbidden
      }.each do |role, expected_status|
        token = access_token_for(user_for_role(role))

        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

        expect(response).to have_http_status(expected_status), "expected #{role} to return #{expected_status}"
      end
    end

    it 'returns a localized forbidden response for a role without permission' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for(hr_user)}",
            'X-Locale' => 'ur'
          }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.forbidden', locale: :ur))
      expect(response.headers['Content-Language']).to eq('ur')
    end

    it 'rejects requests without authentication' do
      get '/api/v1/users'

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects an invalid jwt' do
      get '/api/v1/users', headers: { 'Authorization' => 'Bearer invalid.token' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects a candidate token on a staff-only endpoint' do
      candidate = create(:candidate)
      candidate_session = create(:candidate_session, candidate:)
      token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects revoked staff sessions even with an otherwise valid access token' do
      token = access_token_for(admin)
      Session.last.revoke!

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects inactive staff even with a previously issued token' do
      token = access_token_for(admin)
      admin.update!(active: false)

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
    end

    it 'supports localized responses and falls back when locale is unsupported' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for(admin)}",
            'X-Locale' => 'fr'
          }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Language']).to eq('en')
    end

    it 'applies only explicitly allowed filters' do
      get '/api/v1/users',
          params: { filter: { role: 'hr,mps', active: 'true' }, sort: 'email' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:ok)
      emails = response.parsed_body.fetch('data').map { |entry| entry.fetch('email') }

      expect(emails).to eq(%w[hr@example.com mps@example.com])
    end

    it 'rejects unsupported filters with a field-addressable error' do
      get '/api/v1/users',
          params: { filter: { password_digest: 'nope' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_filter')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.password_digest')
    end

    it 'rejects unsupported sorting with a field-addressable error' do
      get '/api/v1/users',
          params: { sort: '-encrypted_password' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_sort')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('sort.encrypted_password')
    end

    it 'rejects malformed boolean filters' do
      get '/api/v1/users',
          params: { filter: { active: 'sometimes' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_query_parameter')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.active')
    end

    it 'rejects malformed page numbers' do
      get '/api/v1/users',
          params: { page: { number: 'zero' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('page.number')
    end

    it 'rejects oversized page sizes instead of silently capping them' do
      get '/api/v1/users',
          params: { page: { size: 101 } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('page.size')
    end

    it 'rejects unsupported role filter values' do
      get '/api/v1/users',
          params: { filter: { role: 'hr,ghost_role' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.role')
    end

    it 'propagates the request id in headers and response metadata' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for(admin)}",
            'X-Request-Id' => 'request-id-123'
          }

      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Request-Id']).to eq('request-id-123')
      expect(response.parsed_body.dig('meta', 'request_id')).to eq('request-id-123')
    end
  end
end
