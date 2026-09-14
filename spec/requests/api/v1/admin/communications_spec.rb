# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Communications', type: :request do
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

  describe 'GET /api/v1/admin/communications' do
    it 'allows an admin to list communications, most recent first' do
      admin = create(:user, role: 'admin')
      older = travel_to(2.days.ago) { create(:communication) }
      newer = travel_to(1.hour.ago) { create(:communication) }

      get '/api/v1/admin/communications', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([newer.public_id, older.public_id])
    end

    it 'serializes channel, assignment, initiated_by and delivery state' do
      actor = create(:user, role: 'admin')
      assignment = create(:candidate_assignment)
      communication = create(:communication, candidate_assignment: assignment, initiated_by: actor)

      get '/api/v1/admin/communications', headers: auth_headers(actor)

      row = response.parsed_body.dig('data', 0)
      expect(row).to eq(
        'id' => communication.public_id,
        'channel_code' => 'sms',
        'direction_code' => 'outbound',
        'status_code' => 'sent',
        'template_code' => 'welcome_message',
        'locale' => 'en',
        'candidate_assignment' => {
          'id' => assignment.public_id,
          'reference_number' => assignment.reference_number,
          'candidate_id' => assignment.candidate.public_id
        },
        'initiated_by' => { 'id' => actor.public_id, 'role' => 'admin' },
        'recipient_masked' => '+92300*****12',
        'provider_reference' => nil,
        'error_code' => nil,
        'sent_at' => communication.sent_at.utc.iso8601,
        'delivered_at' => nil,
        'failed_at' => nil,
        'created_at' => communication.created_at.utc.iso8601
      )
    end

    it 'allows a management staff member (view_communications) to list too' do
      management = create(:user, role: 'management')
      create(:communication)

      get '/api/v1/admin/communications', headers: auth_headers(management)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
    end

    it 'forbids a staff member without view_communications or manage_communications' do
      finance = create(:user, role: 'finance')

      get '/api/v1/admin/communications', headers: auth_headers(finance)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/communications'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'filters by channel' do
      admin = create(:user, role: 'admin')
      sms = create(:communication, channel_code: 'sms')
      create(:communication, channel_code: 'email')

      get '/api/v1/admin/communications', params: { filter: { channel: 'sms' } }, headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([sms.public_id])
    end

    it 'filters by candidate' do
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      mine = create(:communication, candidate_assignment: assignment)
      create(:communication)

      get '/api/v1/admin/communications', params: { filter: { candidate: candidate.public_id } },
                                          headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([mine.public_id])
    end

    it 'rejects an unsupported filter' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/communications', params: { filter: { bogus: 'x' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.bogus')
    end

    it 'paginates the collection' do
      admin = create(:user, role: 'admin')
      3.times { create(:communication) }

      get '/api/v1/admin/communications', params: { page: { number: 1, size: 2 } }, headers: auth_headers(admin)

      expect(response.parsed_body['data'].size).to eq(2)
      pagination = response.parsed_body.dig('meta', 'pagination')
      expect(pagination).to eq('page' => 1, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2)
    end

    it 'does not N+1 as the number of communications grows' do
      admin = create(:user, role: 'admin')
      create(:communication)

      single_row_count = count_queries do
        get '/api/v1/admin/communications', headers: auth_headers(admin)
      end

      3.times { create(:communication) }
      multi_row_count = count_queries do
        get '/api/v1/admin/communications', headers: auth_headers(admin)
      end

      expect(multi_row_count).to eq(single_row_count)
    end
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == 'SCHEMA'

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
