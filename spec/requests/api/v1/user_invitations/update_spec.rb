# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 User Invitations', type: :request do
  include ActiveJob::TestHelper

  around do |example|
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
  ensure
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  before do
    ensure_staff_authorization_reference_data!
  end

  def invite_user!
    perform_enqueued_jobs do
      post '/api/v1/users',
           params: { user: { email: 'accepted.staff@example.com', role: 'hr' } },
           headers: { 'Authorization' => "Bearer #{admin_access_token}" }
    end

    ActionMailer::Base.deliveries.last.body.encoded[/Invitation token:\s+([A-Za-z0-9._-]+)/, 1]
  end

  def admin_access_token
    admin = create(:user, role: 'admin', password: 'Password123!')
    post '/api/v1/auth/login', params: { auth: { email: admin.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  it 'accepts a valid invitation and activates the invited user' do
    token = invite_user!

    patch '/api/v1/user_invitation',
          params: {
            invitation: {
              token:,
              password: 'Password123!',
              password_confirmation: 'Password123!'
            }
          }

    expect(response).to have_http_status(:ok)
    user = User.find_by!(email: 'accepted.staff@example.com')
    expect(user.reload.staff_state).to eq('active')
    expect(response.parsed_body.dig('data', 'user', 'staff_state')).to eq('active')
  end

  it 'rejects an invalid invitation token with a generic error' do
    patch '/api/v1/user_invitation',
          params: {
            invitation: {
              token: 'not-a-real-token',
              password: 'Password123!',
              password_confirmation: 'Password123!'
            }
          }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_invitation')
  end
end
