# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Users Index', type: :request do
  let!(:admin) { create(:user, role: 'admin', email: 'admin@example.com', password: 'Password123!') }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    create(:user, role: 'hr', email: 'hr@example.com', active: true, created_at: 2.days.ago)
    create(
      :user,
      role: 'finance',
      email: 'finance@example.com',
      active: false,
      created_at: 1.day.ago
    )
    create(:user, role: 'mps', email: 'mps@example.com', active: true, created_at: Time.current)
    example.run
  ensure
    Rails.cache = original_cache
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  it 'returns a paginated collection response with public identifiers' do
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
      'total_count' => 4,
      'total_pages' => 2
    )
    expect(response.parsed_body.fetch('errors')).to eq([])
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
