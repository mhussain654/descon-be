# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AiCallOperationalSettingPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show? and #update?' do
    it 'allows only the developer (manage_ai_call_settings is developer-only)' do
      developer = create(:user, role: 'developer')

      expect(described_class.new(developer, AiCallOperationalSetting).show?).to be(true)
      expect(described_class.new(developer, AiCallOperationalSetting).update?).to be(true)
    end

    it 'denies admin and every other staff role' do
      %w[admin hr mps finance management].each do |role|
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
