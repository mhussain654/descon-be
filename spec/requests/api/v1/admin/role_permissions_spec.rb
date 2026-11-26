# frozen_string_literal: true

require 'rails_helper'

# Developer-only roles and permissions matrix.
RSpec.describe 'API V1 Admin role permissions', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:developer) { create(:user, role: 'developer') }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def save(role_code, codes, user: developer)
    patch "/api/v1/admin/role_permissions/#{role_code}",
          params: { role_permission: { permission_codes: codes } }, headers: headers_for(user), as: :json
  end

  def codes_for(role_code) = Role.find_by!(code: role_code).permissions.pluck(:code).sort

  describe 'GET /api/v1/admin/role_permissions' do
    it 'lists roles, permissions and what each role has' do
      get '/api/v1/admin/role_permissions', headers: headers_for(developer)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data.fetch('roles').find { |role| role['code'] == 'developer' }).to include('locked' => true)
      expect(data.fetch('roles').find do |role|
        role['code'] == 'hr'
      end).to include('locked' => false, 'name' => be_present)
      expect(data.fetch('permissions').find { |permission| permission['code'] == 'manage_reference_data' })
        .to include('developer_only' => true)
      expect(data.dig('grants', 'hr')).to eq(codes_for('hr'))
    end

    it 'is refused to an admin' do
      get '/api/v1/admin/role_permissions', headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/role_permissions/:role_code' do
    it "replaces a role's permissions and records an audit event" do
      expect { save('finance', %w[view_payments view_candidates]) }
        .to change { AuditEvent.where(action_code: 'role_permissions_update').count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(codes_for('finance')).to eq(%w[view_candidates view_payments])
      expect(response.parsed_body.dig('data', 'grants', 'finance')).to eq(%w[view_candidates view_payments])
    end

    it 'refuses to change the developer role' do
      save('developer', %w[view_payments])

      expect(response).to have_http_status(:unprocessable_content)
      expect(codes_for('developer')).to include('manage_reference_data')
    end

    it 'refuses a developer-only permission for another role' do
      before = codes_for('hr')
      save('hr', before + %w[view_job_logs])

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('role_permission.permission_codes')
      expect(codes_for('hr')).to eq(before)
    end

    it 'refuses to take staff management away from admin' do
      save('admin', codes_for('admin') - %w[manage_staff_users])

      expect(response).to have_http_status(:unprocessable_content)
      expect(codes_for('admin')).to include('manage_staff_users')
    end

    it 'refuses an unknown permission' do
      save('hr', %w[not_a_permission])

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns not found for an unknown role' do
      save('ghost', %w[view_candidates])

      expect(response).to have_http_status(:not_found)
    end

    it 'is refused to an admin' do
      save('hr', %w[view_candidates], user: create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
