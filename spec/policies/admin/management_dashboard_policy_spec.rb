# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::ManagementDashboardPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show?' do
    it 'allows staff with an active view_management_dashboard permission (admin, management)' do
      admin = create(:user, role: 'admin')
      management = create(:user, role: 'management')
      denied_actors = %w[hr mps finance].map { |role| create(:user, role:) }

      expect(described_class.new(admin, :management_dashboard).show?).to be(true)
      expect(described_class.new(management, :management_dashboard).show?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, :management_dashboard).show? == false })
      expect(described_class.new(nil, :management_dashboard).show?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_management = create(:user, role: 'management', active: false)

      expect(described_class.new(inactive_management, :management_dashboard).show?).to be(false)
    end

    it 'denies a user when the view_management_dashboard permission record is inactive' do
      management = create(:user, role: 'management')
      Permission.find_by!(code: 'view_management_dashboard').update!(active: false)

      expect(described_class.new(management, :management_dashboard).show?).to be(false)
    end
  end
end
