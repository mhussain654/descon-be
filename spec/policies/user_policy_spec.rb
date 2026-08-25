# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows only staff with the manage_staff_users permission' do
      allowed_actor = create(:user, role: 'admin')
      denied_actors = %w[hr mps finance management].map { |role| create(:user, role:) }

      expect(described_class.new(allowed_actor, User).index?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, User).index? == false })
      expect(described_class.new(nil, User).index?).to be(false)
    end
  end

  describe '#show?' do
    it 'allows only the authenticated staff user to view its own profile' do
      actor = create(:user, role: 'management')
      other_user = create(:user, role: 'admin')

      expect(described_class.new(actor, actor).show?).to be(true)
      expect(described_class.new(actor, other_user).show?).to be(false)
      expect(described_class.new(nil, actor).show?).to be(false)
    end
  end

  describe UserPolicy::Scope do
    let!(:admin) { create(:user, role: 'admin') }
    let!(:hr_user) { create(:user, role: 'hr') }
    let!(:mps_user) { create(:user, role: 'mps') }

    it 'returns the full scope only for staff with the manage_staff_users permission' do
      resolved_scope = described_class.new(admin, User.all).resolve

      expect(resolved_scope).to contain_exactly(admin, hr_user, mps_user)
    end

    it 'returns no rows for staff without the manage_staff_users permission' do
      %w[hr mps finance management].each do |role|
        actor = create(:user, role:)

        expect(described_class.new(actor, User.all).resolve).to be_empty
      end
    end

    it 'returns no rows when unauthenticated' do
      expect(described_class.new(nil, User.all).resolve).to be_empty
    end
  end
end
