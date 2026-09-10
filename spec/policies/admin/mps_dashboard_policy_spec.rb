# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::MpsDashboardPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show?' do
    it 'allows staff with an active view_mps_dashboard permission (admin, mps)' do
      admin = create(:user, role: 'admin')
      mps = create(:user, role: 'mps')
      denied_actors = %w[hr finance management].map { |role| create(:user, role:) }

      expect(described_class.new(admin, :mps_dashboard).show?).to be(true)
      expect(described_class.new(mps, :mps_dashboard).show?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, :mps_dashboard).show? == false })
      expect(described_class.new(nil, :mps_dashboard).show?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_mps = create(:user, role: 'mps', active: false)

      expect(described_class.new(inactive_mps, :mps_dashboard).show?).to be(false)
    end

    it 'denies a user when the view_mps_dashboard permission record is inactive' do
      mps = create(:user, role: 'mps')
      Permission.find_by!(code: 'view_mps_dashboard').update!(active: false)

      expect(described_class.new(mps, :mps_dashboard).show?).to be(false)
    end
  end
end
