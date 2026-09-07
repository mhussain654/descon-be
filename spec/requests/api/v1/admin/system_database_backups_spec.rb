# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin System Database Backups', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}" }
  end

  describe 'GET /api/v1/admin/system_database_backups' do
    it 'allows an admin to list backups, most recent first' do
      admin = create(:user, role: 'admin')
      older = create(:system_database_backup, taken_at: 2.days.ago)
      newer = create(:system_database_backup, taken_at: 1.hour.ago)

      get '/api/v1/admin/system_database_backups', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([newer.public_id, older.public_id])
    end

    it 'serializes status, size, checksum and duration without exposing a direct file URL' do
      admin = create(:user, role: 'admin')
      backup = create(:system_database_backup, :with_archive, status_code: 'succeeded')

      get '/api/v1/admin/system_database_backups', headers: auth_headers(admin)

      row = response.parsed_body.dig('data', 0)
      expect(row).to eq(
        'id' => backup.public_id,
        'status' => 'succeeded',
        'taken_at' => backup.taken_at.utc.iso8601,
        'byte_size' => backup.byte_size,
        'checksum_sha256' => backup.checksum_sha256,
        'duration_seconds' => backup.duration_seconds,
        'error_message' => nil
      )
      expect(response.body).not_to include('rails/active_storage')
    end

    it 'forbids every non-admin role, since backups are infra-sensitive' do
      %w[hr mps finance management].each do |role|
        user = create(:user, role:)

        get '/api/v1/admin/system_database_backups', headers: auth_headers(user)

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/system_database_backups'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/system_database_backups/:system_database_backup_id/access' do
    it 'returns a short-lived signed download URL for an admin' do
      admin = create(:user, role: 'admin')
      backup = create(:system_database_backup, :with_archive)

      post "/api/v1/admin/system_database_backups/#{backup.public_id}/access", headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'backup_id')).to eq(backup.public_id)
      expect(response.parsed_body.dig('data', 'url')).to be_present
      expect(response.parsed_body.dig('data', 'expires_at')).to be_present
    end

    it 'records an audit event for the access' do
      admin = create(:user, role: 'admin')
      backup = create(:system_database_backup, :with_archive)

      post "/api/v1/admin/system_database_backups/#{backup.public_id}/access", headers: auth_headers(admin)

      event = AuditEvent.last
      expect(event.action_code).to eq('system_database_backup_accessed')
      expect(event.actor).to eq(admin)
    end

    it 'returns 422 when the backup has no attached archive' do
      admin = create(:user, role: 'admin')
      backup = create(:system_database_backup, status_code: 'failed')

      post "/api/v1/admin/system_database_backups/#{backup.public_id}/access", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('backup_archive_not_found')
    end

    it 'forbids a non-admin role' do
      management = create(:user, role: 'management')
      backup = create(:system_database_backup, :with_archive)

      post "/api/v1/admin/system_database_backups/#{backup.public_id}/access", headers: auth_headers(management)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
