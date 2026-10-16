# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingVideos::DirectUploadTicketService do
  let(:owner) { create(:user, role: 'admin') }
  let(:valid_params) do
    { filename: 'airport.mp4', byte_size: 1.megabyte, content_type: 'video/mp4',
      checksum: Digest::MD5.base64digest('sample') }
  end

  before do
    ensure_staff_authorization_reference_data!
    # Set per request by the controller; needed to build the direct-upload URL here.
    ActiveStorage::Current.url_options = { protocol: 'https', host: 'api.example.test' }
  end

  def issue(**overrides) = described_class.call(owner:, **valid_params, **overrides)

  it 'returns a signed id plus the direct-upload URL and headers, tagging the blob with its owner' do
    ticket = issue

    expect(ticket.keys).to contain_exactly(:signed_id, :upload_url, :upload_headers)
    expect(ActiveStorage::Blob.find_signed(ticket[:signed_id]).metadata['training_video_owner_id']).to eq(owner.id)
  end

  it 'accepts a size that arrives as a string, as request params do' do
    expect(issue(byte_size: '1048576')).to include(:signed_id)
  end

  {
    'a missing filename' => { filename: '' },
    'a size of zero' => { byte_size: 0 },
    'a size over the limit' => { byte_size: TrainingVideo::MAX_BYTES + 1 },
    'a non-numeric size' => { byte_size: 'big' },
    'a missing size' => { byte_size: nil },
    'a type other than MP4' => { content_type: 'video/quicktime' },
    'a malformed checksum' => { checksum: 'not-a-checksum' }
  }.each do |description, overrides|
    it "refuses #{description} without creating a blob" do
      blobs_before = ActiveStorage::Blob.count

      expect { issue(**overrides) }.to raise_error(TrainingVideos::InvalidFileError)
      expect(ActiveStorage::Blob.count).to eq(blobs_before)
    end
  end
end
