# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Training videos', type: :request do
  before { ensure_staff_authorization_reference_data! }

  def staff_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def candidate_headers(candidate)
    session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session: session)
    { 'Authorization' => "Bearer #{token}" }
  end

  def uploaded_blob(owner, content = "\0\0\0\x18ftypisom".b)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content), filename: 'airport.mp4', content_type: 'video/mp4',
      metadata: { training_video_owner_id: owner.id }, identify: false
    )
  end

  it 'requires the training permission and does not reveal unpublished videos to candidates' do
    admin = create(:user, role: 'admin')
    candidate = create(:candidate)
    blob = uploaded_blob(admin)
    post '/api/v1/admin/training_videos', headers: staff_headers(admin),
                                          params: { training_video: { title_en: 'Airport', title_ur: 'ہوائی اڈہ',
                                                                      file: blob.signed_id } }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    get '/api/v1/candidate/training_videos', headers: candidate_headers(candidate)
    expect(response.parsed_body['data']).to eq([])
    patch "/api/v1/admin/training_videos/#{id}", headers: staff_headers(admin),
                                                 params: { training_video: { published: true } }
    expect(response).to have_http_status(:ok)
    get '/api/v1/candidate/training_videos', headers: candidate_headers(candidate)
    expect(response.parsed_body.dig('data', 0, 'title_en')).to eq('Airport')
    expect(response.parsed_body.dig('data', 0, 'playback_url')).to start_with('http')
  end

  it 'lists every video, including unpublished ones, for authorized staff and refuses everyone else' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')
    blob = uploaded_blob(admin)
    post '/api/v1/admin/training_videos',
         params: { training_video: { title_en: 'Airport', title_ur: 'ہوائی اڈہ', file: blob.signed_id } },
         headers: staff_headers(admin)

    get '/api/v1/admin/training_videos', headers: staff_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 0, 'title_en')).to eq('Airport')
    expect(response.parsed_body.dig('data', 0, 'published')).to be(false)
    expect(response.parsed_body.dig('data', 0, 'playback_url')).to start_with('http')

    get '/api/v1/admin/training_videos', headers: staff_headers(hr)

    expect(response).to have_http_status(:forbidden)
  end

  it 'deletes a video with an audit trail, and refuses staff without the training permission' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')
    post '/api/v1/admin/training_videos', headers: staff_headers(admin),
                                          params: { training_video: { title_en: 'Airport', title_ur: 'ہوائی اڈہ',
                                                                      file: uploaded_blob(admin).signed_id } }
    id = response.parsed_body.dig('data', 'id')

    delete "/api/v1/admin/training_videos/#{id}", headers: staff_headers(hr)
    expect(response).to have_http_status(:forbidden)
    expect(TrainingVideo.exists?(id)).to be(true)

    delete "/api/v1/admin/training_videos/#{id}", headers: staff_headers(admin)
    expect(response).to have_http_status(:no_content)
    expect(TrainingVideo.exists?(id)).to be(false)
    expect(AuditEvent.where(entity_type: 'TrainingVideo', entity_id: id,
                            action_code: 'training_video_deleted')).to exist
  end

  it 'issues a bounded direct upload ticket to authorized staff' do
    admin = create(:user, role: 'admin')
    post '/api/v1/admin/training_videos/upload',
         params: { training_video_upload: { filename: 'airport.mp4', byte_size: 170.megabytes,
                                            content_type: 'video/mp4', checksum: Digest::MD5.base64digest('sample') } },
         headers: staff_headers(admin)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'signed_id')).to be_present
    expect(response.parsed_body.dig('data', 'upload_url')).to be_present
    expect(response.parsed_body.dig('data', 'upload_headers')).to be_a(Hash)

    post '/api/v1/admin/training_videos/upload',
         params: { training_video_upload: { filename: 'oversized.mp4', byte_size: 251.megabytes,
                                            content_type: 'video/mp4', checksum: Digest::MD5.base64digest('sample') } },
         headers: staff_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'does not allow a different staff member to register an uploaded blob' do
    admin = create(:user, role: 'admin')
    other = create(:user, role: 'admin')
    blob = uploaded_blob(admin)
    post '/api/v1/admin/training_videos',
         params: { training_video: { title_en: 'Airport', title_ur: 'ہوائی اڈہ', file: blob.signed_id } },
         headers: staff_headers(other)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects a spoofed video and unauthorized staff upload' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')
    fake = uploaded_blob(admin, 'not an mp4')
    bad_video = { training_video: { title_en: 'Bad', title_ur: 'خراب', file: fake.signed_id } }
    post '/api/v1/admin/training_videos', params: bad_video, headers: staff_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    post '/api/v1/admin/training_videos', params: bad_video, headers: staff_headers(hr)
    expect(response).to have_http_status(:forbidden)
    expect(TrainingVideo.count).to eq(0)
  end
end
