# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingVideos::VideoSerializer do
  let(:owner) { create(:user, role: 'admin') }
  let(:video) do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("\0\0\0\x18ftypisom".b), filename: 'a.mp4',
                                                  content_type: 'video/mp4', identify: false)
    TrainingVideo.new(title_en: 'A', title_ur: 'ا', position: 0, created_by: owner).tap do |record|
      record.file.attach(blob)
      record.save!
    end
  end

  before { ensure_staff_authorization_reference_data! }

  it 'signs the playback link for an hour so seeking and resuming a long video keep working' do
    blob = video.file.blob
    allow(blob).to receive(:url).and_return('https://example.test/signed')

    data = described_class.new(video, include_access: true).as_json

    expect(blob).to have_received(:url).with(expires_in: 1.hour, disposition: :inline)
    expect(data[:playback_url]).to eq('https://example.test/signed')
  end

  it 'does not issue a playback link unless access is requested' do
    expect(described_class.new(video).as_json).not_to have_key(:playback_url)
  end
end
