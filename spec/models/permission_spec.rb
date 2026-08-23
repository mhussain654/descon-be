# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Permission, type: :model do
  subject(:permission) { build(:permission) }

  it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
  it { is_expected.to have_many(:roles).through(:role_permissions) }
  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:permission, code: 'manage_candidates') }
    let(:expected_english_name) { 'Manage candidates' }
    let(:expected_urdu_name) { 'امیدواروں کا انتظام' }
  end

  def system_permission_for(code)
    Permission.find_or_initialize_by(code:).tap do |permission|
      permission.system_defined = true
      permission.active = true
      permission.save! if permission.new_record?
    end
  end

  it 'prevents mutating system-defined permission codes' do
    permission = system_permission_for('manage_candidates')

    permission.code = 'changed'

    expect(permission).not_to be_valid
    expect(permission.errors[:base]).to be_present
  end

  it 'prevents changing system-defined permissions to non-system-defined' do
    permission = system_permission_for('view_candidates')

    permission.system_defined = false

    expect(permission).not_to be_valid
    expect(permission.errors[:base]).to be_present
  end

  it 'prevents destroying system-defined permissions' do
    permission = system_permission_for('view_candidates')

    expect(permission.destroy).to be(false)
  end
end
