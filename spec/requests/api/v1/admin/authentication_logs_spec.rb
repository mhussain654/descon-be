# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Authentication logs', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:candidates_path) { '/api/v1/admin/authentication_logs/candidates' }
  let(:staff_path) { '/api/v1/admin/authentication_logs/staff' }
  let(:developer) { create(:user, role: 'developer') }
  let(:headers) { auth_headers(developer) }

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def data = response.parsed_body.fetch('data')

  describe 'access' do
    it 'is forbidden to every role but developer' do
      %w[admin hr mps finance management].each do |role|
        role_headers = auth_headers(create(:user, role:))

        [candidates_path, staff_path].each do |path|
          get(path, headers: role_headers)

          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    it 'requires a staff login' do
      get candidates_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/authentication_logs/candidates' do
    it 'counts the OTPs sent and sign-ins per candidate, most recent sign-in first' do
      freeze_time
      frequent = create(:candidate, full_name: 'Frequent Signer')
      create(:candidate_assignment, candidate: frequent, registration_number: 900_123)
      create_list(:candidate_otp_challenge, 3, :consumed, candidate: frequent, created_at: 2.days.ago)
      create(:candidate_session, candidate: frequent, created_at: 2.days.ago, last_seen_at: 1.day.ago)
      create(:candidate_session, candidate: frequent, created_at: 3.hours.ago)
      recent = create(:candidate, full_name: 'Recent Signer')
      create(:candidate_otp_challenge, :consumed, candidate: recent)
      create(:candidate_session, candidate: recent, created_at: 1.hour.ago, last_seen_at: 5.minutes.ago)
      never = create(:candidate, full_name: 'Never Signed')
      create(:candidate_otp_challenge, candidate: never)
      create(:candidate_otp_challenge, :decoy)

      get candidates_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(data.pluck('full_name')).to eq(['Recent Signer', 'Frequent Signer', 'Never Signed'])
      expect(data.second).to include(
        'id' => frequent.public_id, 'registration_number' => 900_123, 'otp_count' => 3, 'login_count' => 2,
        'store_review_account' => false
      )
      expect(Time.zone.parse(data.second['last_login_at'])).to eq(3.hours.ago)
      expect(Time.zone.parse(data.second['last_seen_at'])).to eq(3.hours.ago)
      expect(data.third).to include('otp_count' => 1, 'login_count' => 0, 'last_login_at' => nil, 'last_seen_at' => nil)
      expect(data.first['masked_cnic']).to match(/\A\d{5}-\*{7}-\d\z/)
      expect(response.parsed_body.dig('meta', 'pagination')).to include('total_count' => 3)
    end

    it 'searches by name, registration number or CNIC' do
      match = create(:candidate, full_name: 'Zahid Iqbal')
      create(:candidate_assignment, candidate: match, registration_number: 900_777)
      create(:candidate, full_name: 'Someone Else')

      ['zahid', '900777', match.cnic].each do |term|
        get candidates_path, params: { search: term }, headers: headers

        expect(data.pluck('full_name')).to eq(['Zahid Iqbal'])
      end
    end

    it 'filters by whether the candidate has ever signed in, and sorts by a chosen column' do
      signed_in = create(:candidate, full_name: 'B Signed In')
      create(:candidate_session, candidate: signed_in)
      create(:candidate, full_name: 'A Never')

      get candidates_path, params: { filter: { activity: 'never_signed_in' } }, headers: headers
      expect(data.pluck('full_name')).to eq(['A Never'])
      expect(response.parsed_body.dig('meta', 'applied_filters')).to eq('activity' => 'never_signed_in')

      get candidates_path, params: { filter: { activity: 'signed_in' } }, headers: headers
      expect(data.pluck('full_name')).to eq(['B Signed In'])

      get candidates_path, params: { sort: 'full_name' }, headers: headers
      expect(data.pluck('full_name')).to eq(['A Never', 'B Signed In'])
    end

    it 'paginates' do
      create_list(:candidate, 3)

      get candidates_path, params: { page: { number: 2, size: 2 } }, headers: headers

      expect(data.size).to eq(1)
      expect(response.parsed_body.dig('meta', 'pagination')).to eq(
        'page' => 2, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2
      )
    end

    it 'rejects an unknown sort, filter, activity or oversized page' do
      [{ sort: 'cnic' }, { filter: { status: 'x' } }, { filter: { activity: 'sometimes' } },
       { page: { size: 101 } }, { page: { number: 0 } }].each do |params|
        get candidates_path, params:, headers: headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'marks the store review demo account' do
      candidate = create(:candidate)
      allow(StoreReview::Account).to receive(:candidate?).and_call_original
      allow(StoreReview::Account).to receive(:candidate?).with(having_attributes(id: candidate.id)).and_return(true)

      get candidates_path, headers: headers

      expect(data.first['store_review_account']).to be(true)
    end
  end

  describe 'GET /api/v1/admin/authentication_logs/candidates/:id' do
    it "returns the candidate's sign-ins and OTPs, newest first, without any code" do
      candidate = create(:candidate)
      create(:candidate_session, candidate:, created_at: 2.days.ago, revoked_at: 1.day.ago, user_agent: 'okhttp/4')
      create(:candidate_session, candidate:, created_at: 1.hour.ago, last_seen_at: 10.minutes.ago)
      create(:candidate_otp_challenge, :consumed, candidate:, created_at: 1.hour.ago)
      create(:candidate_otp_challenge, :expired, candidate:, created_at: 2.hours.ago)
      create(:candidate_otp_challenge, :locked, candidate:, created_at: 3.hours.ago)
      create(:candidate_otp_challenge, candidate:, created_at: 1.minute.ago)

      get "#{candidates_path}/#{candidate.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(data).to include('id' => candidate.public_id, 'login_count' => 2, 'otp_count' => 4)
      expect(data['sign_ins'].size).to eq(2)
      expect(data['sign_ins'].second).to include('user_agent' => 'okhttp/4', 'ip_address' => '127.0.0.1')
      expect(data['sign_ins'].second['signed_out_at']).to be_present
      expect(data['otps'].pluck('status')).to eq(%w[pending used expired locked])
      expect(response.body).not_to include('code_digest')
    end

    it 'returns 404 for an unknown candidate' do
      get "#{candidates_path}/missing", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'is forbidden to admins' do
      get "#{candidates_path}/#{create(:candidate).public_id}", headers: auth_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/authentication_logs/staff' do
    it 'counts sign-ins per staff account, most recent first' do
      hr = create(:user, role: 'hr', email: 'hr.person@example.com', failed_attempts: 2)
      create(:session, user: hr, created_at: 3.days.ago, last_seen_at: 2.days.ago)
      create(:session, user: hr, created_at: 2.days.ago)
      never = create(:user, role: 'mps', email: 'never@example.com')
      headers

      get staff_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(data.pluck('email')).to eq([developer.email, 'hr.person@example.com', 'never@example.com'])
      expect(data.second).to include('id' => hr.public_id, 'role' => 'hr', 'login_count' => 2, 'failed_attempts' => 2,
                                     'locked' => false, 'staff_state' => 'active')
      expect(data.third).to include('id' => never.public_id, 'login_count' => 0, 'last_login_at' => nil)
    end

    it 'searches by email and sorts by a chosen column' do
      create(:user, email: 'zara@example.com')
      create(:user, email: 'adam@example.com')

      get staff_path, params: { search: 'zara' }, headers: headers
      expect(data.pluck('email')).to eq(['zara@example.com'])

      get staff_path, params: { sort: 'email' }, headers: headers
      expect(data.pick('email')).to eq('adam@example.com')

      get staff_path, params: { sort: 'password' }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'GET /api/v1/admin/authentication_logs/staff/:id' do
    it "lists the account's authentication events newest first, leaving out session refreshes" do
      hr = create(:user, role: 'hr')
      create(:authentication_event, user: hr, event_code: 'login_succeeded', occurred_at: 2.hours.ago)
      create(:authentication_event, user: hr, event_code: 'refresh_succeeded', occurred_at: 90.minutes.ago)
      create(:authentication_event, user: hr, event_code: 'logout_succeeded', occurred_at: 1.hour.ago)

      get "#{staff_path}/#{hr.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(data).to include('id' => hr.public_id, 'email' => hr.email)
      expect(data['events'].pluck('event_code')).to eq(%w[logout_succeeded login_succeeded])
    end

    it 'returns 404 for an unknown account' do
      get "#{staff_path}/missing", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
