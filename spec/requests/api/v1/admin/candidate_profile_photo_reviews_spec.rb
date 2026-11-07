# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Profile Photo Reviews', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate) }
  let(:base_path) { "/api/v1/admin/candidates/#{candidate.public_id}/profile_photo" }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def give_candidate_a_photo
    Candidates::ProfilePhotos::UpdateService.call(
      candidate:, uploaded_file: fixture_upload('test.jpg', 'image/jpeg'), request_id: SecureRandom.uuid
    )
  end

  it 'marks a new upload as waiting for review' do
    give_candidate_a_photo

    expect(candidate.reload.profile_photo_status).to eq('pending')
  end

  it 'shows staff the photo and its status on the candidate' do
    give_candidate_a_photo

    get "/api/v1/admin/candidates/#{candidate.public_id}", headers: headers_for(create(:user, role: 'admin'))

    expect(response.parsed_body.dig('data', 'profile_photo')).to include(
      'status' => 'pending', 'url' => start_with('/rails/active_storage/blobs/proxy/')
    )
  end

  it 'approves the photo' do
    give_candidate_a_photo
    admin = create(:user, role: 'admin')

    post "#{base_path}/approval", headers: headers_for(admin)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('data')).to include('status' => 'approved')
    expect(candidate.reload).to have_attributes(profile_photo_status: 'approved', profile_photo_reviewed_by: admin)
    expect(candidate.profile_photo).to be_attached
    expect(AuditEvent.find_by(candidate:, action_code: 'candidate_profile_photo_approved')).to be_present
  end

  it 'rejects the photo, removes it and tells the candidate in their profile' do
    give_candidate_a_photo

    post "#{base_path}/rejection", headers: headers_for(create(:user, role: 'admin'))

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('data')).to include('status' => 'rejected', 'url' => nil)
    expect(candidate.reload.profile_photo_status).to eq('rejected')
    expect(AuditEvent.find_by(candidate:, action_code: 'candidate_profile_photo_rejected')).to be_present

    profile = Candidates::ProfileSerializer.new(candidate.reload).as_json
    expect(profile).to include(photo_status: 'rejected', photo_url: nil)
  end

  it 'says there is nothing to review when the candidate has no photo' do
    post "#{base_path}/approval", headers: headers_for(create(:user, role: 'admin'))

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('candidate_profile_photo_not_found')
  end

  it 'forbids staff who cannot review documents' do
    give_candidate_a_photo

    post "#{base_path}/approval", headers: headers_for(create(:user, role: 'finance'))

    expect(response).to have_http_status(:forbidden)
    expect(candidate.reload.profile_photo_status).to eq('pending')
  end

  it 'clears the status when the candidate removes their own photo' do
    give_candidate_a_photo

    Candidates::ProfilePhotos::RemoveService.call(candidate:, request_id: SecureRandom.uuid)

    expect(candidate.reload.profile_photo_status).to be_nil
  end
end
