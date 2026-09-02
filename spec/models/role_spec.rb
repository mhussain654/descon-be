# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Role, type: :model do
  subject(:role) { build(:role) }

  it { is_expected.to have_many(:users).with_foreign_key(:role).with_primary_key(:code) }
  it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
  it { is_expected.to have_many(:permissions).through(:role_permissions) }
  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:role, code: 'admin') }
    let(:expected_english_name) { 'Administrator' }
    let(:expected_urdu_name) { 'منتظم' }
  end

  def system_role_for(code)
    Role.find_or_initialize_by(code:).tap do |system_role|
      system_role.system_defined = true
      system_role.active = true
      system_role.save! if system_role.new_record?
    end
  end

  it 'prevents mutating system-defined role codes' do
    system_role = system_role_for('hr')

    system_role.code = 'changed'

    expect(system_role).not_to be_valid
    expect(system_role.errors[:base]).to be_present
  end

  it 'prevents changing system-defined roles to non-system-defined' do
    system_role = system_role_for('mps')

    system_role.system_defined = false

    expect(system_role).not_to be_valid
    expect(system_role.errors[:base]).to be_present
  end

  it 'prevents destroying system-defined roles' do
    system_role = create(:role, code: 'system_test_role', system_defined: true)

    expect(system_role.destroy).to be(false)
  end
end
