# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate SMS Sender', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:candidate) { create(:candidate) }
  let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/sms_sender" }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  def change_sender(sender, user: create(:user, role: 'hr'))
    patch path, params: { sms_sender: { sender: } }.to_json, headers: headers_for(user)
  end

  describe 'PATCH /api/v1/admin/candidates/:candidate_id/sms_sender' do
    it 'moves the candidate to the short code' do
      change_sender('short_code')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'sender')).to eq('short_code')
      expect(candidate.reload.sms_sender).to eq('short_code')
    end

    it 'moves the candidate back to the brand name' do
      candidate.update!(sms_sender: 'short_code')

      change_sender('masking', user: create(:user, role: 'admin'))

      expect(response).to have_http_status(:ok)
      expect(candidate.reload.sms_sender).to eq('masking')
    end

    it 'rejects an unknown sender with a field error' do
      change_sender('whatsapp')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].first).to include('code' => 'validation_failed',
                                                              'field' => 'sms_sender.sender')
      expect(candidate.reload.sms_sender).to eq('masking')
    end

    it 'returns 400 without the sms_sender object' do
      patch path, params: {}.to_json, headers: headers_for(create(:user))

      expect(response).to have_http_status(:bad_request)
      expect(candidate.reload.sms_sender).to eq('masking')
    end

    it 'returns 404 to staff whose role cannot open candidates' do
      finance = Role.find_by!(code: 'finance')
      RolePermission.where(role_id: finance.id).delete_all

      change_sender('short_code', user: create(:user, role: 'finance'))

      expect(response).to have_http_status(:not_found)
      expect(candidate.reload.sms_sender).to eq('masking')
    end

    it 'returns 404 for an unknown candidate' do
      patch '/api/v1/admin/candidates/00000000-0000-0000-0000-000000000000/sms_sender',
            params: { sms_sender: { sender: 'short_code' } }.to_json, headers: headers_for(create(:user))

      expect(response).to have_http_status(:not_found)
    end

    it 'requires a staff access token' do
      patch path, params: { sms_sender: { sender: 'short_code' } }.to_json,
                  headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
      expect(candidate.reload.sms_sender).to eq('masking')
    end
  end
end
