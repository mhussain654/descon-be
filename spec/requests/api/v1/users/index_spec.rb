# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Users Index', type: :request do
  let(:admin_email) { 'admin@example.com' }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  before do
    ensure_staff_authorization_reference_data!

    create(:user, role: 'admin', email: admin_email, password: 'Password123!')
    create(:user, role: 'hr', email: 'hr@example.com', password: 'Password123!', active: true, created_at: 2.days.ago)
    create(
      :user,
      role: 'mps',
      email: 'mps@example.com',
      password: 'Password123!',
      active: true,
      created_at: Time.current
    )
    create(:user, role: 'finance', email: 'finance-active@example.com', password: 'Password123!', active: true)
    create(:user, role: 'management', email: 'management@example.com', password: 'Password123!', active: true)
    create(
      :user,
      role: 'finance',
      email: 'finance-disabled@example.com',
      password: 'Password123!',
      active: false,
      created_at: 1.day.ago
    )
  end

  def user_by_email(email)
    User.find_by!(email:)
  end

  def access_token_for(email)
    post '/api/v1/auth/login', params: { auth: { email:, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def access_token_for_role(role)
    email = {
      admin: admin_email,
      hr: 'hr@example.com',
      mps: 'mps@example.com',
      finance: 'finance-active@example.com',
      management: 'management@example.com'
    }.fetch(role)

    access_token_for(email)
  end

  describe 'GET /api/v1/users' do
    it 'returns a paginated collection response with public identifiers for admins' do
      get '/api/v1/users',
          params: { page: { number: 1, size: 2 }, sort: 'email' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

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
    end

    it 'allows the admin role and forbids every other supported active staff role' do
      {
        admin: :ok,
        hr: :forbidden,
        mps: :forbidden,
        finance: :forbidden,
        management: :forbidden
      }.each do |role, expected_status|
        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{access_token_for_role(role)}" }

        expect(response).to have_http_status(expected_status), "expected #{role} to return #{expected_status}"
      end
    end

    it 'returns a localized forbidden response for a role without permission' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for_role(:hr)}",
            'X-Locale' => 'ur'
          }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.forbidden', locale: :ur))
      expect(response.headers['Content-Language']).to eq('ur')
    end

    it 'denies access when the role is inactive' do
      user_by_email(admin_email).staff_role.update!(active: false)

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'denies access when the required permission is inactive' do
      Permission.find_by!(code: 'manage_staff_users').update!(active: false)

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
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
      token = access_token_for(admin_email)
      Session.last.revoke!

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects inactive staff even with a previously issued token' do
      token = access_token_for(admin_email)
      user_by_email(admin_email).update!(active: false)

      get '/api/v1/users', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
    end

    it 'supports localized responses and falls back when locale is unsupported' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for(admin_email)}",
            'X-Locale' => 'fr'
          }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Language']).to eq('en')
    end

    it 'applies only explicitly allowed filters' do
      get '/api/v1/users',
          params: { filter: { role: 'hr,mps', active: 'true' }, sort: 'email' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:ok)
      emails = response.parsed_body.fetch('data').map { |entry| entry.fetch('email') }

      expect(emails).to eq(%w[hr@example.com mps@example.com])
    end

    it 'rejects unsupported filters with a field-addressable error' do
      get '/api/v1/users',
          params: { filter: { password_digest: 'nope' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_filter')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.password_digest')
    end

    it 'rejects unsupported sorting with a field-addressable error' do
      get '/api/v1/users',
          params: { sort: '-encrypted_password' },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_sort')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('sort.encrypted_password')
    end

    it 'rejects malformed boolean filters' do
      get '/api/v1/users',
          params: { filter: { active: 'sometimes' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_query_parameter')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.active')
    end

    it 'rejects malformed page numbers' do
      get '/api/v1/users',
          params: { page: { number: 'zero' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('page.number')
    end

    it 'rejects oversized page sizes instead of silently capping them' do
      get '/api/v1/users',
          params: { page: { size: 101 } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('page.size')
    end

    it 'rejects unsupported role filter values' do
      get '/api/v1/users',
          params: { filter: { role: 'hr,ghost_role' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(admin_email)}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.role')
    end

    it 'propagates the request id in headers and response metadata' do
      get '/api/v1/users',
          headers: {
            'Authorization' => "Bearer #{access_token_for(admin_email)}",
            'X-Request-Id' => 'request-id-123'
          }

      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Request-Id']).to eq('request-id-123')
      expect(response.parsed_body.dig('meta', 'request_id')).to eq('request-id-123')
    end
  end
end
