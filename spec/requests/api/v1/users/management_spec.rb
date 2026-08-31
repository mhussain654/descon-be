# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Users Management', type: :request do
  include ActiveJob::TestHelper

  let(:admin_password) { 'Password123!' }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
  ensure
    Rails.cache = original_cache
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: admin_password } }
    response.parsed_body.dig('data', 'access_token')
  end

  describe 'POST /api/v1/users' do
    it 'allows an authorized admin to invite a staff user' do
      admin = create(:user, role: 'admin', password: admin_password)

      perform_enqueued_jobs do
        post '/api/v1/users',
             params: { user: { email: 'invited.staff@example.com', role: 'hr' } },
             headers: { 'Authorization' => "Bearer #{login_as(admin)}" }
      end

      expect(response).to have_http_status(:created)
      invited_user = User.find_by!(email: 'invited.staff@example.com')
      expect(invited_user.staff_state).to eq('invited')
      expect(response.parsed_body.dig('data', 'user', 'staff_state')).to eq('invited')
      expect(response.parsed_body.dig('data', 'user')).not_to have_key('invitation_token_digest')
      expect(ActionMailer::Base.deliveries.last.to).to eq([invited_user.email])
      expect(
        AuditEvent.where(action_code: 'staff_user_invited', entity_type: 'User', entity_id: invited_user.id)
      ).to exist
    end

    it 'forbids a staff user without manage_staff_users permission' do
      hr_user = create(:user, role: 'hr', password: admin_password)

      post '/api/v1/users',
           params: { user: { email: 'forbidden.staff@example.com', role: 'mps' } },
           headers: { 'Authorization' => "Bearer #{login_as(hr_user)}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects duplicate email addresses with a field-addressable validation error' do
      admin = create(:user, role: 'admin', password: admin_password)
      create(:user, email: 'duplicate.staff@example.com')

      post '/api/v1/users',
           params: { user: { email: 'duplicate.staff@example.com', role: 'finance' } },
           headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('email')
    end

    it 'rejects invalid roles' do
      admin = create(:user, role: 'admin', password: admin_password)

      post '/api/v1/users',
           params: { user: { email: 'invalid-role@example.com', role: 'ghost_role' } },
           headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('role')
    end

    it 'rejects unsupported fields' do
      admin = create(:user, role: 'admin', password: admin_password)

      post '/api/v1/users',
           params: { user: { email: 'mass-assign@example.com', role: 'hr', active: true } },
           headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('user.active')
    end

    it 'returns Urdu validation messages when requested' do
      admin = create(:user, role: 'admin', password: admin_password)

      post '/api/v1/users',
           params: { user: { email: 'mass-assign-ur@example.com', role: 'hr', active: true } },
           headers: { 'Authorization' => "Bearer #{login_as(admin)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(
        I18n.t('api.errors.unsupported_attribute', locale: :ur)
      )
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end

  describe 'PATCH /api/v1/users/:id' do
    it 'allows an authorized admin to change role and revokes the target sessions immediately' do
      admin = create(:user, role: 'admin', password: admin_password, email: 'acting-admin@example.com')
      target = create(:user, role: 'hr', password: admin_password, email: 'target-user@example.com')
      target_access_token = login_as(target)

      patch "/api/v1/users/#{target.public_id}",
            params: { user: { role: 'finance' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'user', 'role')).to eq('finance')

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{target_access_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not revoke unrelated sessions when updating a staff user' do
      admin = create(:user, role: 'admin', password: admin_password, email: 'actor-2@example.com')
      target = create(:user, role: 'hr', password: admin_password, email: 'target-2@example.com')
      unrelated = create(:user, role: 'mps', password: admin_password, email: 'unrelated@example.com')
      unrelated_access_token = login_as(unrelated)

      patch "/api/v1/users/#{target.public_id}",
            params: { user: { role: 'finance' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{unrelated_access_token}" }
      expect(response).to have_http_status(:ok)
    end

    it 'rejects self-suspension' do
      admin = create(:user, role: 'admin', password: admin_password)

      patch "/api/v1/users/#{admin.public_id}",
            params: { user: { staff_state: 'suspended' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('user.staff_state')
    end

    it 'rejects suspending the final active admin' do
      admin = create(:user, role: 'admin', password: admin_password)

      patch "/api/v1/users/#{admin.public_id}",
            params: { user: { staff_state: 'suspended' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.last_active_admin'))
    end

    it 'rejects demoting the final active admin' do
      admin = create(:user, role: 'admin', password: admin_password)

      patch "/api/v1/users/#{admin.public_id}",
            params: { user: { role: 'hr' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('user.role')
    end

    it 'rejects invalid staff states' do
      admin = create(:user, role: 'admin', password: admin_password)
      target = create(:user, role: 'hr', password: admin_password)

      patch "/api/v1/users/#{target.public_id}",
            params: { user: { staff_state: 'ghost_state' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('staff_state')
    end

    it 'rejects unsupported fields on update' do
      admin = create(:user, role: 'admin', password: admin_password)
      target = create(:user, role: 'hr', password: admin_password)

      patch "/api/v1/users/#{target.public_id}",
            params: { user: { role: 'finance', email: 'nope@example.com' } },
            headers: { 'Authorization' => "Bearer #{login_as(admin)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('user.email')
    end
  end
end
