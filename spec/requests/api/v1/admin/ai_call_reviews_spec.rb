# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin AI Call Reviews', type: :request do
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

  def needs_review_call
    communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'inbound')
    communication.create_candidate_ai_call!(
      direction: 'inbound', call_reason: 'general_helpline', language_code: 'en', status: 'completed',
      verification_status: 'pending', outcome: nil, outcome_reason: 'needs_manual_review'
    )
  end

  describe 'POST /api/v1/admin/ai_calls/:ai_call_id/review' do
    it 'resolves a needs_manual_review call, recording who decided what and why' do
      admin = create(:user, role: 'admin')
      call_record = needs_review_call

      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'answered', outcome_reason: 'resolved', notes: 'Listened to the recording.' }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'outcome')).to eq('answered')
      expect(response.parsed_body.dig('data', 'outcome_reason')).to eq('resolved')
      expect(response.parsed_body.dig('data', 'review_notes')).to eq('Listened to the recording.')
      expect(response.parsed_body.dig('data', 'reviewed_by', 'id')).to eq(admin.public_id)
      expect(response.parsed_body.dig('data', 'reviewed_at')).to be_present

      event = call_record.candidate_ai_call_events.find_by!(event_type: 'manual_outcome_resolved')
      expect(event.actor).to eq(admin)
      expect(event.payload).to eq('selected_outcome' => 'answered', 'reason' => 'Listened to the recording.')
    end

    it 'rejects an unrecognized outcome' do
      admin = create(:user, role: 'admin')
      call_record = needs_review_call

      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'bogus' }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('outcome')
    end

    it 'rejects resolving a call that is not awaiting manual review' do
      admin = create(:user, role: 'admin')
      call_record = needs_review_call
      call_record.update!(outcome: 'answered', outcome_reason: 'resolved')

      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'answered' }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('ai_call_not_awaiting_review')
    end

    # Regression: a second resolution attempt must not be allowed to
    # silently overwrite a call's already-recorded outcome.
    it 'rejects a second resolution attempt after the call has already been resolved' do
      admin = create(:user, role: 'admin')
      call_record = needs_review_call
      request_headers = auth_headers(admin).merge('Content-Type' => 'application/json')

      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'answered', outcome_reason: 'resolved' }.to_json, headers: request_headers
      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'callback_required', outcome_reason: 'candidate_requested' }.to_json,
           headers: request_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(call_record.reload.outcome).to eq('answered')
      expect(call_record.candidate_ai_call_events.where(event_type: 'manual_outcome_resolved').count).to eq(1)
    end

    it 'forbids a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')
      call_record = needs_review_call

      post "/api/v1/admin/ai_calls/#{call_record.public_id}/review",
           params: { outcome: 'answered' }.to_json,
           headers: auth_headers(finance).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:not_found)
    end
  end
end
