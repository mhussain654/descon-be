# frozen_string_literal: true

require 'rails_helper'

# Roles and permissions matrix (manage_reference_data, the developer role by default).
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
      expect(data.fetch('roles').find { |role| role['code'] == 'developer' }).to include('locked' => true,
                                                                                         'own_role' => true)
      expect(data.fetch('roles').find do |role|
        role['code'] == 'hr'
      end).to include('locked' => false, 'own_role' => false, 'name' => be_present)
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

    it 'gives and takes developer-only permissions to and from another role' do
      before = codes_for('hr')
      save('hr', before + %w[view_job_logs send_candidate_otp])

      expect(response).to have_http_status(:ok)
      expect(codes_for('hr')).to include('view_job_logs', 'send_candidate_otp')
      expect(create(:user, role: 'hr').permission?('send_candidate_otp')).to be(true)

      save('hr', before)
      expect(codes_for('hr')).to eq(before)
    end

    it "refuses to let a role given manage_reference_data change its own permissions, but not another role's" do
      save('admin', codes_for('admin') + %w[manage_reference_data])
      admin = create(:user, role: 'admin')
      admin_before = codes_for('admin')

      save('admin', admin_before + %w[view_job_logs], user: admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'message'))
        .to eq('You cannot change the permissions of your own role.')
      expect(codes_for('admin')).to eq(admin_before)

      save('finance', %w[view_payments], user: admin)
      expect(response).to have_http_status(:ok)
      expect(codes_for('finance')).to eq(%w[view_payments])
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
