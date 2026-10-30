# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CommunicationPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows every active staff role: the log is a read-only report' do
      %w[developer admin management hr mps finance].each do |role|
        expect(described_class.new(create(:user, role:), Communication).index?).to be(true)
      end
      expect(described_class.new(nil, Communication).index?).to be(false)
    end

    it 'denies an inactive staff member' do
      inactive_admin = create(:user, role: 'admin', active: false)

      expect(described_class.new(inactive_admin, Communication).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for active staff and none for an inactive one' do
      finance = create(:user, role: 'finance')
      inactive_admin = create(:user, role: 'admin', active: false)
      create(:communication)

      expect(described_class::Scope.new(finance, Communication.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(inactive_admin, Communication.all).resolve.count).to eq(0)
    end
  end
end
