# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Boarding Pass', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate, status_code: 'flight_details_uploaded') }
  let(:assignment) do
    create(:candidate_assignment, candidate:,
                                  current_workflow_stage: WorkflowStage.find_by!(code: 'flight_details_uploaded'))
  end

  def candidate_headers(for_candidate = candidate)
    candidate_session = create(:candidate_session, candidate: for_candidate)
    { 'Authorization' => "Bearer #{CandidateAuthentication::TokenIssuer.call(candidate: for_candidate, candidate_session:)}" }
  end

  def staff_headers(role: 'mps')
    user = create(:user, role:)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def upload(file, headers: candidate_headers)
    put '/api/v1/candidate/flight_detail/boarding_pass', params: { boarding_pass: { photo: file } }, headers:
  end

  describe 'PUT /api/v1/candidate/flight_detail/boarding_pass' do
    context 'when the flight is recorded' do
      let!(:detail) { create(:candidate_flight_detail, candidate_assignment: assignment) }

      it 'stores the photo under a neutral name, records when, and audits it' do
        freeze_time do
          upload(fixture_upload('test.jpg', 'image/jpeg'))

          expect(response).to have_http_status(:ok)
          expect(response.headers['Cache-Control']).to eq('private, no-store')
          expect(response.parsed_body.dig('data', 'boarding_pass_uploaded_at')).to eq(Time.current.utc.iso8601)
          expect(detail.reload.boarding_pass).to be_attached
          expect(detail.boarding_pass.filename.to_s).to eq('boarding-pass.jpg')
          expect(detail.boarding_pass_uploaded_at).to eq(Time.current)
          expect(AuditEvent.find_by(candidate:, action_code: 'candidate_boarding_pass_uploaded')).to be_present
        end
      end

      it 'replaces an earlier photo' do
        upload(fixture_upload('test.jpg', 'image/jpeg'))
        first_blob_id = detail.reload.boarding_pass.blob.id

        upload(fixture_upload('test.png', 'image/png'))

        expect(response).to have_http_status(:ok)
        expect(detail.reload.boarding_pass.blob.id).not_to eq(first_blob_id)
        expect(detail.boarding_pass.content_type).to eq('image/png')
      end

      it 'marks the boarding pass as uploaded in the application progress' do
        upload(fixture_upload('test.jpg', 'image/jpeg'))

        get '/api/v1/candidate/application_progress', headers: candidate_headers

        expect(response.parsed_body.dig('data', 'workflow', 'outcomes', 'boarding_pass')).to eq('uploaded')
      end

      it 'rejects a non-image by its real content, whatever the client declares' do
        upload(fixture_upload('test.pdf', 'image/jpeg'))

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0)).to include('code' => 'unsupported_file_type',
                                                                 'field' => 'boarding_pass.photo')
        expect(detail.reload.boarding_pass_uploaded_at).to be_nil
      end

      it 'rejects a missing file' do
        put '/api/v1/candidate/flight_detail/boarding_pass', params: { boarding_pass: { photo: '' } },
                                                             headers: candidate_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_file')
      end

      it 'rejects a file over the size limit' do
        stub_const('CandidateWorkflows::FlightDetails::BoardingPassUploadService::MAX_FILE_BYTES', 10)

        upload(fixture_upload('test.jpg', 'image/jpeg'))

        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('file_too_large')
      end
    end

    it 'returns not found before staff have recorded the flight' do
      assignment

      upload(fixture_upload('test.jpg', 'image/jpeg'))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an unauthenticated request' do
      put '/api/v1/candidate/flight_detail/boarding_pass',
          params: { boarding_pass: { photo: fixture_upload('test.jpg', 'image/jpeg') } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/flight_detail/boarding_pass_access' do
    let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail/boarding_pass_access" }

    before { create(:candidate_flight_detail, candidate_assignment: assignment) }

    it 'gives staff a short-lived link to the uploaded photo and audits it' do
      upload(fixture_upload('test.jpg', 'image/jpeg'))

      post path, headers: staff_headers

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.dig('data', 'url')).to start_with('/rails/active_storage/blobs/proxy/')
      expect(AuditEvent.where(action_code: 'candidate_boarding_pass_accessed').where.not(actor: nil).count).to eq(1)
    end

    it 'reports a missing file while the candidate has not uploaded one' do
      post path, headers: staff_headers

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_attachment_missing')
    end

    it 'refuses a candidate token' do
      post path, headers: candidate_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
