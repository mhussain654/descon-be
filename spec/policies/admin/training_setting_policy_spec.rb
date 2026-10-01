# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::TrainingSettingPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show? and #update?' do
    it 'allows only admin (manage_training_settings is admin-only by default)' do
      admin = create(:user, role: 'admin')

      expect(described_class.new(admin, TrainingSetting).show?).to be(true)
      expect(described_class.new(admin, TrainingSetting).update?).to be(true)
    end

    it 'denies every non-admin role' do
      %w[hr mps finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, TrainingSetting).show?).to be(false)
        expect(described_class.new(actor, TrainingSetting).update?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, TrainingSetting).show?).to be(false)
    end
  end
end
