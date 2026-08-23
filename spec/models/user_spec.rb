# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it { is_expected.to belong_to(:staff_role).class_name('Role').with_foreign_key(:role).with_primary_key(:code) }
  it { is_expected.to have_many(:sessions).dependent(:destroy) }
  it { is_expected.to validate_uniqueness_of(:public_id) }

  it 'assigns a public_id on create' do
    user.public_id = nil

    user.validate

    expect(user.public_id).to be_present
  end

  it 'normalizes email addresses' do
    user.email = ' ADMIN@EXAMPLE.COM '
    user.validate

    expect(user.email).to eq('admin@example.com')
  end

  it 'answers permission checks through the assigned role' do
    role = Role.find_by!(code: 'admin')
    permission = Permission.find_by!(code: 'manage_candidates')
    RolePermission.find_or_create_by!(role:, permission:)
    user = create(:user, role: role.code)

    expect(user.admin?).to be(true)
    expect(user.permission?('manage_candidates')).to be(true)
    expect(user.permission?('unknown_permission')).to be(false)
  end
end
