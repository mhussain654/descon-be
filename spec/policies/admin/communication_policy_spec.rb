# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CommunicationPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows only the developer: the Communications menu is developer-only' do
      expect(described_class.new(create(:user, role: 'developer'), Communication).index?).to be(true)
      %w[admin management hr finance].each do |role|
        expect(described_class.new(create(:user, role:), Communication).index?).to be(false)
      end
      expect(described_class.new(nil, Communication).index?).to be(false)
    end

    it 'denies an inactive developer' do
      inactive_developer = create(:user, role: 'developer', active: false)

      expect(described_class.new(inactive_developer, Communication).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for a permitted actor and none for a denied one' do
      developer = create(:user, role: 'developer')
      management = create(:user, role: 'management')
      create(:communication)

      expect(described_class::Scope.new(developer, Communication.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(management, Communication.all).resolve.count).to eq(0)
    end
  end
end
