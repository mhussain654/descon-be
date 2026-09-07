# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AdminDashboardPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#show?' do
    it 'allows staff with an active view_admin_dashboard permission (admin)' do
      admin = create(:user, role: 'admin')
      denied_actors = %w[hr mps finance management].map { |role| create(:user, role:) }

      expect(described_class.new(admin, :admin_dashboard).show?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, :admin_dashboard).show? == false })
      expect(described_class.new(nil, :admin_dashboard).show?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_admin = create(:user, role: 'admin', active: false)

      expect(described_class.new(inactive_admin, :admin_dashboard).show?).to be(false)
    end

    it 'denies a user when the view_admin_dashboard permission record is inactive' do
      admin = create(:user, role: 'admin')
      Permission.find_by!(code: 'view_admin_dashboard').update!(active: false)

      expect(described_class.new(admin, :admin_dashboard).show?).to be(false)
    end
  end
end
