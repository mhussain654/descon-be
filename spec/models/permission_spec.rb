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

  it 'prevents mutating system-defined permission codes' do
    permission = create(:permission, code: 'manage_candidates', system_defined: true)

    permission.code = 'changed'

    expect(permission).not_to be_valid
    expect(permission.errors[:base]).to be_present
  end

  it 'prevents changing system-defined permissions to non-system-defined' do
    permission = create(:permission, code: 'view_candidates', system_defined: true)

    permission.system_defined = false

    expect(permission).not_to be_valid
    expect(permission.errors[:base]).to be_present
  end

  it 'prevents destroying system-defined permissions' do
    permission = create(:permission, code: 'view_candidates', system_defined: true)

    expect(permission.destroy).to be(false)
  end
end
