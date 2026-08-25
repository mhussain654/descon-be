# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows only staff with an active role and active manage_staff_users permission' do
      admin = create(:user, role: 'admin')
      denied_actors = %w[hr mps finance management].map { |role| create(:user, role:) }

      expect(described_class.new(admin, User).index?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, User).index? == false })
      expect(described_class.new(nil, User).index?).to be(false)
    end

    it 'denies an inactive user by policy' do
      inactive_admin = create(:user, role: 'admin', active: false)

      expect(described_class.new(inactive_admin, User).index?).to be(false)
    end

    it 'denies a user with an inactive role' do
      admin = create(:user, role: 'admin')
      admin.staff_role.update!(active: false)

      expect(described_class.new(admin, User).index?).to be(false)
    end

    it 'denies a user when the permission record is inactive' do
      admin = create(:user, role: 'admin')
      Permission.find_by!(code: 'manage_staff_users').update!(active: false)

      expect(described_class.new(admin, User).index?).to be(false)
    end

    it 'denies a user when the role-permission assignment is removed' do
      admin = create(:user, role: 'admin')
      role_permission = RolePermission.joins(:role, :permission)
                                      .find_by!(roles: { code: 'admin' }, permissions: { code: 'manage_staff_users' })
      role_permission.destroy!

      expect(described_class.new(admin, User).index?).to be(false)
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

    it 'denies profile access for a user with an inactive role' do
      actor = create(:user, role: 'management')
      actor.staff_role.update!(active: false)

      expect(described_class.new(actor, actor).show?).to be(false)
    end
  end

  describe UserPolicy::Scope do
    before do
      create(:user, role: 'hr')
      create(:user, role: 'mps')
    end

    it 'returns the full scope only for staff with the manage_staff_users permission' do
      admin = create(:user, role: 'admin')

      resolved_scope = described_class.new(admin, User.all).resolve

      expect(resolved_scope).to match_array(User.all)
    end

    it 'returns no rows for staff without the manage_staff_users permission' do
      %w[hr mps finance management].each do |role|
        actor = create(:user, role:)

        expect(described_class.new(actor, User.all).resolve).to be_empty
      end
    end

    it 'returns no rows when the staff role is inactive' do
      admin = create(:user, role: 'admin')
      admin.staff_role.update!(active: false)

      expect(described_class.new(admin, User.all).resolve).to be_empty
    end

    it 'returns no rows when unauthenticated' do
      expect(described_class.new(nil, User.all).resolve).to be_empty
    end
  end
end
