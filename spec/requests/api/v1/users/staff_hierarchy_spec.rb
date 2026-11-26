# frozen_string_literal: true

require 'rails_helper'

# Staff see and manage accounts only at or below their own level: developer
# above admin, admin above the functional roles.
RSpec.describe 'API V1 Staff users hierarchy', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let!(:developer) { create(:user, role: 'developer') }
  let!(:admin) { create(:user, role: 'admin') }
  let!(:hr) { create(:user, role: 'hr') }
  let!(:finance) { create(:user, role: 'finance') }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def listed_emails(user)
    get '/api/v1/users', params: { page: { size: 100 } }, headers: headers_for(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('data').pluck('email')
  end

  # Gives a functional role the staff-management permission, to check it stays within its own role.
  def grant_staff_management!(role_code)
    RolePermission.find_or_create_by!(role: Role.find_by!(code: role_code),
                                      permission: Permission.find_by!(code: 'manage_staff_users'))
  end

  it 'shows a developer every account' do
    expect(listed_emails(developer)).to include(developer.email, admin.email, hr.email, finance.email)
  end

  it 'never shows developers to an admin' do
    emails = listed_emails(admin)

    expect(emails).to include(admin.email, hr.email, finance.email)
    expect(emails).not_to include(developer.email)
  end

  it 'treats a developer account as not found for an admin' do
    patch "/api/v1/users/#{developer.public_id}", params: { user: { staff_state: 'suspended' } },
                                                  headers: headers_for(admin)

    expect(response).to have_http_status(:not_found)
    expect(developer.reload.staff_state).not_to eq('suspended')
  end

  context 'when a functional role may manage staff' do
    before { grant_staff_management!('hr') }

    it 'shows only accounts of its own role' do
      emails = listed_emails(hr)

      expect(emails).to include(hr.email)
      expect(emails).not_to include(admin.email, developer.email, finance.email)
    end

    it 'cannot give a role above its own' do
      post '/api/v1/users', params: { user: { email: 'new-admin@example.com', role: 'admin' } },
                            headers: headers_for(hr)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0)).to include('field' => 'user.role',
                                                               'message' => I18n.t('api.errors.role_above_own'))
    end

    it 'cannot see or change an account of another role' do
      patch "/api/v1/users/#{finance.public_id}", params: { user: { staff_state: 'suspended' } },
                                                  headers: headers_for(hr)

      expect(response).to have_http_status(:not_found)
    end
  end
end
