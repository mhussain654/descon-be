# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CommunicationPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows staff with view_communications or manage_communications' do
      admin = create(:user, role: 'admin')
      management = create(:user, role: 'management')
      hr = create(:user, role: 'hr')
      denied = create(:user, role: 'finance')

      expect(described_class.new(admin, Communication).index?).to be(true)
      expect(described_class.new(management, Communication).index?).to be(true)
      expect(described_class.new(hr, Communication).index?).to be(true)
      expect(described_class.new(denied, Communication).index?).to be(false)
      expect(described_class.new(nil, Communication).index?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_management = create(:user, role: 'management', active: false)

      expect(described_class.new(inactive_management, Communication).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for a permitted actor and none for a denied one' do
      management = create(:user, role: 'management')
      finance = create(:user, role: 'finance')
      create(:communication)

      expect(described_class::Scope.new(management, Communication.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(finance, Communication.all).resolve.count).to eq(0)
    end
  end
end
