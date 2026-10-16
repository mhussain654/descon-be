# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingVideos::CreateService do
  let(:creator) { create(:user, role: 'admin') }
  let(:attributes) { { title_en: 'Airport', title_ur: 'ہوائی اڈہ', position: 0, published: false } }

  before { ensure_staff_authorization_reference_data! }

  def blob_for(owner_id: creator.id, content: "\0\0\0\x18ftypisom".b, content_type: 'video/mp4')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content), filename: 'airport.mp4', content_type:,
      metadata: { training_video_owner_id: owner_id }, identify: false
    )
  end

  def register(blob) = described_class.call(creator:, attributes:, signed_blob_id: blob.signed_id)

  it 'creates the video from an acceptable uploaded blob' do
    video = register(blob_for)

    expect(video).to be_persisted
    expect(video.created_by).to eq(creator)
    expect(video.file).to be_attached
  end

  it 'refuses an unknown or tampered signed id' do
    expect { described_class.call(creator:, attributes:, signed_blob_id: 'tampered') }
      .to raise_error(TrainingVideos::InvalidFileError)
  end

  it "refuses another staff member's upload" do
    expect { register(blob_for(owner_id: create(:user, role: 'admin').id)) }
      .to raise_error(TrainingVideos::InvalidFileError)
  end

  it 'refuses a blob that is already attached to a video' do
    blob = blob_for
    register(blob)

    expect { register(blob) }.to raise_error(TrainingVideos::InvalidFileError)
  end

  it 'refuses an upload older than the registration window' do
    blob = blob_for

    travel_to(blob.created_at + described_class::REGISTRATION_WINDOW + 1.minute) do
      expect { register(blob) }.to raise_error(TrainingVideos::InvalidFileError)
    end
  end

  it 'refuses a blob declared as another type' do
    expect { register(blob_for(content_type: 'application/pdf')) }.to raise_error(TrainingVideos::InvalidFileError)
  end

  it 'refuses a file that does not start like an MP4' do
    expect { register(blob_for(content: 'not an mp4 file at all')) }.to raise_error(TrainingVideos::InvalidFileError)
  end
end
