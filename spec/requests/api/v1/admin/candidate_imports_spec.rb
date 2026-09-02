# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Imports', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_candidate_import_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def uploaded_csv(content, filename: 'candidates.csv', content_type: 'text/csv')
    tempfile = Tempfile.new([File.basename(filename, '.csv'), '.csv'])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, content_type, original_filename: filename)
  end

  def csv_content(*rows)
    CSV.generate do |csv|
      csv << %w[
        full_name
        cnic
        mobile_number
        reference_number
        preferred_locale
        candidate_status
        workflow_stage_code
        country_code
        project_code
        craft_code
        active
      ]
      rows.each { |row| csv << row }
    end
  end

  describe 'POST /api/v1/admin/candidate_imports' do
    it 'allows authorized staff to import candidates' do
      actor = create(:user, role: 'hr', email: 'hr-import@example.com', password: 'Password123!')

      post '/api/v1/admin/candidate_imports',
           params: {
             candidate_import: {
               file: uploaded_csv(
                 csv_content(
                   ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered',
                    'qatar', 'qatar_infrastructure', 'electrician', 'true']
                 )
               )
             }
           },
           headers: { 'Authorization' => "Bearer #{login_as(actor)}" }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'successful_rows')).to eq(1)
      expect(Candidate.count).to eq(1)
      expect(CandidateAssignment.count).to eq(1)
    end

    it 'rejects unauthorized staff and inactive staff safely' do
      %w[mps finance management].each do |role|
        actor = create(:user, role:, email: "#{role}-import@example.com", password: 'Password123!')

        post '/api/v1/admin/candidate_imports',
             params: { candidate_import: { file: uploaded_csv(csv_content) } },
             headers: { 'Authorization' => "Bearer #{login_as(actor)}" }

        expect(response).to have_http_status(:forbidden)
      end

      inactive_actor = create(:user, role: 'hr', email: 'inactive-import@example.com', password: 'Password123!', active: false)

      post '/api/v1/admin/candidate_imports',
           params: { candidate_import: { file: uploaded_csv(csv_content) } },
           headers: { 'Authorization' => "Bearer #{login_as(inactive_actor)}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects requests without authentication or with a candidate token' do
      post '/api/v1/admin/candidate_imports', params: { candidate_import: { file: uploaded_csv(csv_content) } }
      expect(response).to have_http_status(:unauthorized)

      candidate = create(:candidate)
      candidate_session = create(:candidate_session, candidate:)
      token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)

      post '/api/v1/admin/candidate_imports',
           params: { candidate_import: { file: uploaded_csv(csv_content) } },
           headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'replays the same successful import response without creating duplicates when the request is retried with the same idempotency key' do
      actor = create(:user, role: 'hr', email: 'hr-idempotent@example.com', password: 'Password123!')
      headers = {
        'Authorization' => "Bearer #{login_as(actor)}",
        'Idempotency-Key' => 'candidate-import-001'
      }

      post '/api/v1/admin/candidate_imports',
           params: {
             candidate_import: {
               file: uploaded_csv(
                 csv_content(
                   ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered',
                    'qatar', 'qatar_infrastructure', 'electrician', 'true']
                 )
               )
             }
           },
           headers: headers
      expect(response).to have_http_status(:created)

      expect do
        post '/api/v1/admin/candidate_imports',
             params: {
               candidate_import: {
                 file: uploaded_csv(
                   csv_content(
                     ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered',
                      'qatar', 'qatar_infrastructure', 'electrician', 'true']
                   )
                 )
               }
             },
             headers: headers
      end.not_to change(Candidate, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
    end

    it 'integrates with candidate OTP so an imported active candidate receives OTP delivery to the stored mobile and verifies into their own session' do
      actor = create(:user, role: 'hr', email: 'hr-flow@example.com', password: 'Password123!')
      delivered_to = nil
      allow(Sms::SendMessage).to receive(:call) do |**kwargs|
        delivered_to = kwargs.fetch(:to)
        Sms::DeliveryResult.new(success: true, provider_reference: SecureRandom.uuid)
      end

      post '/api/v1/admin/candidate_imports',
           params: {
             candidate_import: {
               file: uploaded_csv(
                 csv_content(
                   ['Imported Candidate', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered',
                    'qatar', 'qatar_infrastructure', 'electrician', 'true']
                 )
               )
             }
           },
           headers: { 'Authorization' => "Bearer #{login_as(actor)}" }

      expect(response).to have_http_status(:created)

      post '/api/v1/candidate/auth/otp/request', params: { candidate: { cnic: '42101-1234567-1' } }
      expect(response).to have_http_status(:ok)
      expect(delivered_to).to eq('+923001234567')

      raw_code = CandidateOtpChallenge.generate_for(candidate: Candidate.find_by!(cnic: '42101-1234567-1')).fetch(:code)
      post '/api/v1/candidate/auth/otp/verify',
           params: { candidate: { cnic: '42101-1234567-1', otp: raw_code } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'candidate', 'id')).to eq(Candidate.find_by!(cnic: '42101-1234567-1').public_id)
    end
  end

  describe 'MPS-307 preflight and commit' do
    def versioned_csv
      headers = Admin::Candidates::Imports::CsvFileParser::SUPPORTED_HEADERS
      values = {
        'full_name' => 'Preflight Candidate', 'cnic' => '42101-1234567-1', 'mobile_number' => '+923001234567',
        'reference_number' => 'DES-001001', 'preferred_locale' => 'en', 'candidate_status' => 'registered',
        'workflow_stage_code' => 'registered', 'country_code' => 'qatar', 'project_code' => 'qatar_infrastructure',
        'craft_code' => 'electrician', 'active' => 'true', 'passport_number' => '', 'next_of_kin_name' => '',
        'next_of_kin_relationship' => '', 'next_of_kin_mobile_number' => '', 'next_of_kin_cnic' => '',
        'template_version' => 'v1'
      }
      CSV.generate do |csv|
        csv << headers
        csv << headers.map { |header| values.fetch(header) }
      end
    end

    it 'preflights and commits the server-side snapshot' do
      actor = create(:user, role: 'hr', password: 'Password123!')
      headers = { 'Authorization' => "Bearer #{login_as(actor)}", 'Idempotency-Key' => 'mps-307-commit' }
      post '/api/v1/admin/candidate_imports/preflight',
           params: { candidate_import: { file: uploaded_csv(versioned_csv) } }, headers: headers
      expect(response).to have_http_status(:created)
      token = response.parsed_body.dig('data', 'preflight_token')

      post '/api/v1/admin/candidate_imports/commit',
           params: { candidate_import: { preflight_token: token } }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'imported_rows')).to eq(1)
    end

    it 'forbids preflight and commit for staff without candidate-management permission' do
      actor = create(:user, role: 'mps', password: 'Password123!')
      headers = { 'Authorization' => "Bearer #{login_as(actor)}" }
      post '/api/v1/admin/candidate_imports/preflight',
           params: { candidate_import: { file: uploaded_csv(versioned_csv) } }, headers: headers
      expect(response).to have_http_status(:forbidden)
      post '/api/v1/admin/candidate_imports/commit',
           params: { candidate_import: { preflight_token: 'invalid-token' } }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
