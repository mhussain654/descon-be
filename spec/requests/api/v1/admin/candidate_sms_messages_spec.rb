# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate SMS Messages', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:candidate) { create(:candidate, full_name: 'Daim Javed', preferred_locale: 'ur') }
  let!(:assignment) { create(:candidate_assignment, candidate:) }
  let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/sms_messages" }

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def headers_for(user, idempotency_key: SecureRandom.uuid)
    { 'Authorization' => "Bearer #{login_as(user)}", 'Content-Type' => 'application/json',
      'Idempotency-Key' => idempotency_key }.compact
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/sms_messages' do
    it 'lists the sendable messages with their languages and filled-in values, and the SMS history' do
      create(:sms_template, message_code: 'visa_issued', template_id_en: '30010', template_id_ur: '30011')
      create(:sms_template, message_code: 'medical_unfit', template_id_en: '20010', enabled: false)
      create(:sms_template, message_code: 'flight_details', template_id_en: nil)
      CandidateSmsDelivery.create!(candidate:, candidate_assignment: assignment, message_code: 'registered',
                                   dedupe_key: 'registered:1', locale: 'ur', status: 'sent')

      get path, headers: headers_for(create(:user, role: 'hr'))

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data['default_locale']).to eq('ur')
      expect(data['messages'].pluck('message_code')).to eq(%w[medical_unfit visa_issued])
      expect(data['messages'].last).to include(
        'automatic' => true, 'locales' => %w[en ur], 'variables' => %w[country],
        'prefilled' => { 'en' => { 'country' => assignment.country.name_en },
                         'ur' => { 'country' => assignment.country.name_ur } }
      )
      expect(data['messages'].first).to include('automatic' => false, 'locales' => %w[en],
                                                'prefilled' => include('en' => { 'name' => 'Daim Javed' }))
      expect(data['deliveries'].sole).to include('message_code' => 'registered', 'status' => 'sent', 'sent_by' => nil)
    end

    it 'forbids a role without send_candidate_sms' do
      get path, headers: headers_for(create(:user, role: 'finance'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/sms_messages' do
    let(:staff) { create(:user, role: 'admin') }
    let(:body) do
      { sms_message: { message_code: 'visa_issued', locale: 'ur', variables: { country: 'قطر' } } }.to_json
    end

    before { create(:sms_template, message_code: 'visa_issued', template_id_en: '30010', template_id_ur: '30011') }

    it 'queues the chosen SMS in the chosen language, recording who sent it' do
      expect { post path, params: body, headers: headers_for(staff) }.to have_enqueued_job(CandidateSms::DeliveryJob)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('data')).to include(
        'message_code' => 'visa_issued', 'locale' => 'ur', 'status' => 'pending',
        'sent_by' => { 'id' => staff.public_id, 'role' => 'admin' }
      )
      expect(CandidateSmsDelivery.sole.variables).to eq('country' => 'قطر')
    end

    it 'sends once for a retried Idempotency-Key' do
      headers = headers_for(staff)
      2.times { post path, params: body, headers: }

      expect(CandidateSmsDelivery.count).to eq(1)
    end

    it 'names the missing value' do
      post path, params: { sms_message: { message_code: 'visa_issued', locale: 'en', variables: {} } }.to_json,
                 headers: headers_for(staff)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('sms_message.variables.country')
    end

    it 'requires an Idempotency-Key header' do
      post path, params: body, headers: headers_for(staff, idempotency_key: nil)

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_idempotency_key')
    end

    it 'forbids a role without send_candidate_sms' do
      post path, params: body, headers: headers_for(create(:user, role: 'management'))

      expect(response).to have_http_status(:forbidden)
      expect(CandidateSmsDelivery.count).to eq(0)
    end
  end
end
