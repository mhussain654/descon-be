# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Import History', type: :request do
  include ActiveJob::TestHelper

  before { ensure_staff_authorization_reference_data! }

  def token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def headers_for(user, idempotency_key: nil, locale: nil)
    headers = { 'Authorization' => "Bearer #{token_for(user)}" }
    headers['Idempotency-Key'] = idempotency_key if idempotency_key
    headers['X-Locale'] = locale if locale
    headers
  end

  it 'lists only the authenticated actor batches with filters and pagination' do
    actor = create(:user, role: 'hr', password: 'Password123!')
    own_batch = create(:candidate_import_batch, actor:, status: 'failed', template_version: 'v2')
    own_batch.update!(created_at: Time.zone.parse('2026-09-01 12:00:00 UTC'))
    create(:candidate_import_batch, actor: create(:user, role: 'hr'), status: 'failed', template_version: 'v2')

    get '/api/v1/admin/candidate_imports', params: {
      filter: { status: 'failed', actor_id: actor.public_id, template_version: 'v2', created_from: '2026-09-01' },
      page: { number: 1, size: 1 }
    }, headers: headers_for(actor)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').map { |batch| batch.fetch('id') }).to eq([own_batch.public_id])
    expect(response.parsed_body.dig('meta', 'pagination')).to include('page' => 1, 'per_page' => 1, 'total_count' => 1)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
  end

  it 'returns a safe detail, localized error export, and no encrypted payload or token data' do
    actor = create(:user, role: 'hr', password: 'Password123!')
    batch = create(:candidate_import_batch, actor:)
    row_result = create(
      :candidate_import_row_result,
      candidate_import_batch: batch,
      status: 'rejected',
      error_field: 'cnic',
      error_code: 'invalid_cnic'
    )

    get "/api/v1/admin/candidate_imports/#{batch.public_id}", headers: headers_for(actor)

    expect(response).to have_http_status(:ok)
    detail = response.parsed_body['data']
    expect(detail.fetch('row_results')).to include(
      hash_including('row_number' => row_result.row_number, 'error_code' => 'invalid_cnic')
    )
    expect(detail).not_to have_key('preflight_payload')
    expect(response.body).not_to include(batch.token_digest)

    get "/api/v1/admin/candidate_imports/#{batch.public_id}/error_export", headers: headers_for(actor, locale: 'ur')

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv')
    expect(response.headers['Content-Disposition']).to include("candidate-import-#{batch.public_id}-errors.csv")
    expect(response.body).to include(I18n.t('api.candidate_imports.row_errors.invalid_cnic', locale: :ur))
  end

  it 'prevents access to another actor batch and unauthorized staff' do
    owner = create(:user, role: 'hr', password: 'Password123!')
    other = create(:user, role: 'hr', password: 'Password123!')
    batch = create(:candidate_import_batch, actor: owner)

    get "/api/v1/admin/candidate_imports/#{batch.public_id}", headers: headers_for(other)
    expect(response).to have_http_status(:not_found)

    unauthorized = create(:user, role: 'mps', password: 'Password123!')
    get '/api/v1/admin/candidate_imports', headers: headers_for(unauthorized)
    expect(response).to have_http_status(:forbidden)
  end

  it 'retries a failed batch once and safely replays the idempotent request' do
    actor = create(:user, role: 'hr', password: 'Password123!')
    batch = create(:candidate_import_batch, actor:, status: 'failed', enqueued_at: 1.hour.ago)
    headers = headers_for(actor, idempotency_key: 'candidate-import-retry-1')

    clear_enqueued_jobs
    post "/api/v1/admin/candidate_imports/#{batch.public_id}/retry", headers: headers

    expect(response).to have_http_status(:accepted)
    expect(batch.reload).to have_attributes(status: 'queued', error_code: nil)
    expect(enqueued_jobs.count { |job| job.fetch(:job) == Admin::CandidateImports::ExecuteJob }).to eq(1)

    post "/api/v1/admin/candidate_imports/#{batch.public_id}/retry", headers: headers

    expect(response).to have_http_status(:accepted)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(enqueued_jobs.count { |job| job.fetch(:job) == Admin::CandidateImports::ExecuteJob }).to eq(1)
  end
end
