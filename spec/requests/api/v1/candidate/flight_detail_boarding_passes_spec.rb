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

  # Inside the upload window (2 days before the flight's day to 2 days after).
  let(:flight_tomorrow) { 1.day.from_now.change(hour: 14, min: 30) }

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
      let!(:detail) do
        create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: flight_tomorrow)
      end

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

        detail.reload.update!(boarding_pass_rejected_at: Time.current, boarding_pass_rejected_by: create(:user),
                              boarding_pass_rejection_reason: 'Not a boarding pass')
        get '/api/v1/candidate/application_progress', headers: candidate_headers
        expect(response.parsed_body.dig('data', 'workflow', 'outcomes', 'boarding_pass')).to be_nil
      end

      it 'queues the OCR check of the new photo' do
        expect { upload(fixture_upload('test.jpg', 'image/jpeg')) }
          .to have_enqueued_job(CandidateWorkflows::FlightDetails::BoardingPassCheckJob)
          .with(detail.id, satisfy { |uploaded_at|
                             uploaded_at == detail.reload.boarding_pass_uploaded_at.utc.iso8601(6)
                           })
        expect(detail.boarding_pass_check).to eq('pending')
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

  describe 'the upload window (Pakistan days, 2 before to 2 after the flight)' do
    # A flight at 02:00 Pakistan time on 27 Nov is still 26 Nov in UTC; the window follows Pakistan's day.
    let!(:detail) do
      create(:candidate_flight_detail, candidate_assignment: assignment,
                                       flight_departure_at: Time.find_zone!('Asia/Karachi').local(2026, 11, 27, 2, 0))
    end

    def upload_on(time)
      travel_to(time) { upload(fixture_upload('test.jpg', 'image/jpeg')) }
    end

    def pakistan(day, hour)
      Time.find_zone!('Asia/Karachi').local(2026, 11, day, hour, 0)
    end

    it 'refuses an upload before the window opens and says from when' do
      upload_on(pakistan(24, 23))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('boarding_pass_upload_not_open')
      expect(response.parsed_body.dig('errors', 0, 'message')).to include('25/11/2026')
      expect(detail.reload.boarding_pass).not_to be_attached
    end

    it 'accepts uploads from the first to the last day of the window' do
      upload_on(pakistan(25, 0))
      expect(response).to have_http_status(:ok)

      upload_on(pakistan(29, 23))
      expect(response).to have_http_status(:ok)
    end

    it 'refuses an upload after the window closes' do
      upload_on(pakistan(30, 0))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('boarding_pass_upload_closed')
    end

    it 'tells the app the window and where today falls' do
      travel_to(pakistan(24, 12)) { get '/api/v1/candidate/flight_detail', headers: candidate_headers }

      expect(response.parsed_body.dig('data', 'boarding_pass_upload'))
        .to eq('opens_on' => '2026-11-25', 'closes_on' => '2026-11-29', 'state' => 'not_yet_open')
    end
  end

  describe 'POST /api/v1/candidate/flight_detail/boarding_pass_access' do
    let(:path) { '/api/v1/candidate/flight_detail/boarding_pass_access' }

    context 'when the flight is recorded' do
      before do
        create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: flight_tomorrow)
      end

      it 'gives the candidate a short-lived link to their own photo and audits it as theirs' do
        upload(fixture_upload('test.jpg', 'image/jpeg'))

        post path, headers: candidate_headers

        expect(response).to have_http_status(:ok)
        expect(response.headers['Cache-Control']).to eq('private, no-store')
        expect(response.parsed_body.dig('data', 'url')).to start_with('/rails/active_storage/blobs/proxy/')
        expect(response.parsed_body.dig('data', 'url')).to include('boarding-pass.jpg')
        event = AuditEvent.find_by!(candidate:, action_code: 'candidate_boarding_pass_accessed')
        expect(event.actor).to be_nil
        expect(event.metadata['accessed_by']).to eq('candidate')
      end

      it 'reports a missing file before the candidate has uploaded one' do
        post path, headers: candidate_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_attachment_missing')
      end

      it "never serves another candidate's photo" do
        upload(fixture_upload('test.jpg', 'image/jpeg'))
        other = create(:candidate, status_code: 'flight_details_uploaded')
        create(:candidate_assignment, candidate: other,
                                      current_workflow_stage: WorkflowStage.find_by!(code: 'flight_details_uploaded'))

        post path, headers: candidate_headers(other)

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'returns not found before staff have recorded the flight' do
      assignment

      post path, headers: candidate_headers

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an unauthenticated request' do
      post path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a staff token' do
      post path, headers: staff_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/flight_detail/boarding_pass_access' do
    let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail/boarding_pass_access" }

    before { create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: flight_tomorrow) }

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
