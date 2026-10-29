# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AppFeatureSettingPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show? and #update?' do
    it 'allows only the developer (manage_app_settings is developer-only)' do
      admin = create(:user, role: 'developer')

      expect(described_class.new(admin, AppFeatureSetting).show?).to be(true)
      expect(described_class.new(admin, AppFeatureSetting).update?).to be(true)
    end

    it 'denies every non-admin role' do
      %w[admin hr mps finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, AppFeatureSetting).show?).to be(false)
        expect(described_class.new(actor, AppFeatureSetting).update?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, AppFeatureSetting).show?).to be(false)
    end
  end
end
