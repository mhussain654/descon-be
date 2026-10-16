# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::TrainingVideoPolicy do
  before { ensure_staff_authorization_reference_data! }

  it 'grants every action only to staff with the training permission' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')

    %i[index? create? update? destroy?].each do |action|
      expect(described_class.new(admin, TrainingVideo).public_send(action)).to be(true)
      expect(described_class.new(hr, TrainingVideo).public_send(action)).to be(false)
    end
  end

  describe 'Scope' do
    it 'returns every video to authorized staff and none to others' do
      admin = create(:user, role: 'admin')
      hr = create(:user, role: 'hr')
      video = create_training_video(admin)

      expect(described_class::Scope.new(admin, TrainingVideo).resolve).to contain_exactly(video)
      expect(described_class::Scope.new(hr, TrainingVideo).resolve).to be_empty
    end

    def create_training_video(owner)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("\0\0\0\x18ftypisom".b), filename: 'a.mp4',
                                                    content_type: 'video/mp4', identify: false)
      TrainingVideo.new(title_en: 'A', title_ur: 'ا', position: 0, created_by: owner).tap do |video|
        video.file.attach(blob)
        video.save!
      end
    end
  end
end
