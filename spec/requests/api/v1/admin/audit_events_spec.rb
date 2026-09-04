# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Audit Events', type: :request do
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

  def audit_event_for(actor: create(:user, role: 'admin'), action_code: 'candidate_document_verified',
                      entity_type: 'CandidateDocument', occurred_at: Time.current, candidate: nil)
    assignment = create(:candidate_assignment, candidate: candidate || create(:candidate))
    create(:audit_event, actor:, candidate: assignment.candidate, candidate_assignment: assignment,
                         action_code:, entity_type:, entity_id: assignment.id, occurred_at:,
                         metadata: { candidate_public_id: assignment.candidate.public_id })
  end

  describe 'GET /api/v1/admin/audit_events' do
    it 'allows an admin to list audit events, most recent first' do
      admin = create(:user, role: 'admin')
      older = audit_event_for(action_code: 'candidate_document_rejected', occurred_at: 2.days.ago)
      newer = audit_event_for(action_code: 'candidate_document_verified', occurred_at: 1.hour.ago)

      get '/api/v1/admin/audit_events', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([newer.id, older.id])
    end

    it 'serializes actor, action, entity, candidate and metadata without exposing raw sensitive values' do
      actor = create(:user, role: 'admin', email: 'reviewer@descon.com')
      event = audit_event_for(actor:)

      get '/api/v1/admin/audit_events', headers: auth_headers(actor)

      row = response.parsed_body.dig('data', 0)
      expect(row).to eq(
        'id' => event.id,
        'actor' => { 'id' => actor.public_id, 'role' => 'admin' },
        'action_code' => 'candidate_document_verified',
        'entity_type' => 'CandidateDocument',
        'entity_id' => event.entity_id,
        'candidate_id' => event.candidate.public_id,
        'reason_code' => nil,
        'note' => nil,
        'request_id' => event.request_id,
        'occurred_at' => event.occurred_at.utc.iso8601,
        'metadata' => { 'candidate_public_id' => event.candidate.public_id }
      )
    end

    it 'allows a management staff member (view_audit_events) to list too' do
      management = create(:user, role: 'management')
      audit_event_for

      get '/api/v1/admin/audit_events', headers: auth_headers(management)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
    end

    it 'forbids a staff member without view_audit_events' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/audit_events', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/audit_events'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'filters by actor' do
      admin = create(:user, role: 'admin')
      other_actor = create(:user, role: 'admin')
      mine = audit_event_for(actor: admin)
      audit_event_for(actor: other_actor)

      get '/api/v1/admin/audit_events', params: { filter: { actor: admin.public_id } }, headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([mine.id])
    end

    it 'filters by a comma-separated action list' do
      admin = create(:user, role: 'admin')
      verified = audit_event_for(action_code: 'candidate_document_verified')
      audit_event_for(action_code: 'candidate_document_rejected')
      audit_event_for(action_code: 'payment_corrected', entity_type: 'Payment')

      get '/api/v1/admin/audit_events', params: { filter: { action: 'candidate_document_verified,payment_corrected' } },
                                        headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to contain_exactly(verified.id, response.parsed_body['data'].find { |r|
        r['action_code'] == 'payment_corrected'
      }['id'])
    end

    it 'filters by entity_type' do
      admin = create(:user, role: 'admin')
      document_event = audit_event_for(entity_type: 'CandidateDocument')
      audit_event_for(entity_type: 'Payment', action_code: 'payment_corrected')

      get '/api/v1/admin/audit_events', params: { filter: { entity_type: 'CandidateDocument' } },
                                        headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([document_event.id])
    end

    it 'filters by candidate' do
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      mine = audit_event_for(candidate:)
      audit_event_for

      get '/api/v1/admin/audit_events', params: { filter: { candidate: candidate.public_id } },
                                        headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([mine.id])
    end

    it 'filters by an occurred_at date range' do
      admin = create(:user, role: 'admin')
      in_range = audit_event_for(occurred_at: Time.zone.parse('2026-06-15 10:00:00'))
      audit_event_for(occurred_at: Time.zone.parse('2026-01-01 10:00:00'))

      get '/api/v1/admin/audit_events',
          params: { filter: { occurred_from: '2026-06-01', occurred_to: '2026-06-30' } },
          headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([in_range.id])
    end

    it 'rejects an unsupported filter' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/audit_events', params: { filter: { bogus: 'x' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.bogus')
    end

    it 'rejects an unknown actor filter value' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/audit_events', params: { filter: { actor: 'not-a-real-id' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.actor')
    end

    it 'rejects occurred_from after occurred_to' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/audit_events',
          params: { filter: { occurred_from: '2026-06-30', occurred_to: '2026-06-01' } },
          headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.occurred_to')
    end

    it 'paginates the collection' do
      admin = create(:user, role: 'admin')
      3.times { audit_event_for }

      get '/api/v1/admin/audit_events', params: { page: { number: 1, size: 2 } }, headers: auth_headers(admin)

      expect(response.parsed_body['data'].size).to eq(2)
      pagination = response.parsed_body.dig('meta', 'pagination')
      expect(pagination).to eq('page' => 1, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2)
    end
  end
end
