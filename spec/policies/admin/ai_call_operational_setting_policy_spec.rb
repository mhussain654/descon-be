# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AiCallOperationalSettingPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show? and #update?' do
    it 'allows only admin (manage_ai_call_settings is admin-only by default)' do
      admin = create(:user, role: 'admin')

      expect(described_class.new(admin, AiCallOperationalSetting).show?).to be(true)
      expect(described_class.new(admin, AiCallOperationalSetting).update?).to be(true)
    end

    it 'denies staff with manage_ai_call_scripts/trigger_ai_calls but not manage_ai_call_settings' do
      %w[hr mps finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, AiCallOperationalSetting).show?).to be(false)
        expect(described_class.new(actor, AiCallOperationalSetting).update?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, AiCallOperationalSetting).show?).to be(false)
    end
  end
end
