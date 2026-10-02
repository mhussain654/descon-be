# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Profile Photo', type: :request do
  before do
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate) }

  def headers_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
    { 'Authorization' => "Bearer #{token}" }
  end

  def upload(file, as: candidate)
    put '/api/v1/candidate/profile/photo', params: { profile_photo: { photo: file } }, headers: headers_for(as)
  end

  describe 'PUT /api/v1/candidate/profile/photo' do
    it 'stores the photo under a neutral filename and returns a short-lived signed link' do
      upload(fixture_upload('test.jpg', 'image/jpeg'))

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.dig('data', 'photo_url')).to start_with('/rails/active_storage/blobs/proxy/')
      expect(candidate.reload.profile_photo).to be_attached
      expect(candidate.profile_photo.filename.to_s).to eq('profile-photo.jpg')
      expect(AuditEvent.find_by(candidate:, action_code: 'candidate_profile_photo_updated')).to be_present
    end

    it 'replaces an existing photo' do
      upload(fixture_upload('test.jpg', 'image/jpeg'))
      first_blob_id = candidate.reload.profile_photo.blob.id

      upload(fixture_upload('test.png', 'image/png'))

      expect(response).to have_http_status(:ok)
      expect(candidate.reload.profile_photo.blob.id).not_to eq(first_blob_id)
      expect(candidate.profile_photo.content_type).to eq('image/png')
    end

    it 'rejects a non-image by its real content, whatever the client declares' do
      upload(fixture_upload('test.pdf', 'image/jpeg'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0)).to include('code' => 'unsupported_file_type',
                                                               'field' => 'profile_photo.photo')
      expect(candidate.reload.profile_photo).not_to be_attached
    end

    it 'rejects a missing file' do
      put '/api/v1/candidate/profile/photo', params: { profile_photo: { photo: '' } }, headers: headers_for(candidate)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_file')
    end

    it 'rejects a file over the size limit' do
      stub_const('Candidates::ProfilePhotos::UpdateService::MAX_FILE_BYTES', 10)

      upload(fixture_upload('test.jpg', 'image/jpeg'))

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('file_too_large')
    end

    it 'rejects an unauthenticated request' do
      put '/api/v1/candidate/profile/photo',
          params: { profile_photo: { photo: fixture_upload('test.jpg', 'image/jpeg') } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/candidate/profile/photo' do
    it 'removes the photo and audits it' do
      upload(fixture_upload('test.jpg', 'image/jpeg'))

      delete '/api/v1/candidate/profile/photo', headers: headers_for(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'photo_url')).to be_nil
      expect(candidate.reload.profile_photo).not_to be_attached
      expect(AuditEvent.find_by(candidate:, action_code: 'candidate_profile_photo_removed')).to be_present
    end

    it 'is a harmless no-op when there is no photo' do
      expect do
        delete '/api/v1/candidate/profile/photo', headers: headers_for(candidate)
      end.not_to change(AuditEvent, :count)

      expect(response).to have_http_status(:ok)
    end
  end

  it "only ever changes the signed-in candidate's own photo" do
    other = create(:candidate)

    upload(fixture_upload('test.jpg', 'image/jpeg'), as: other)

    expect(other.reload.profile_photo).to be_attached
    expect(candidate.reload.profile_photo).not_to be_attached
  end
end
