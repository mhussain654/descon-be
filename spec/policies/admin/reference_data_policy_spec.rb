# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::ReferenceDataPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  def strip_permission!(role_code, permission_code)
    RolePermission.joins(:role, :permission)
                  .find_by!(roles: { code: role_code }, permissions: { code: permission_code })
                  .destroy!
  end

  it 'allows index for view-candidates and manage-candidates roles alike' do
    mps = create(:user, role: 'mps')
    hr = create(:user, role: 'hr')

    expect(described_class.new(mps, :reference_data).index?).to be(true)
    expect(described_class.new(hr, :reference_data).index?).to be(true)
  end

  it 'denies index for a role with neither permission' do
    strip_permission!('finance', 'view_candidates')
    actor = create(:user, role: 'finance')

    expect(described_class.new(actor, :reference_data).index?).to be(false)
  end

  it 'allows managing reference data only to developers (manage_reference_data)' do
    developer = create(:user, role: 'developer')
    policy = described_class.new(developer, :reference_data)

    %i[create? update? retire? manage? restore? destroy?].each { |rule| expect(policy.public_send(rule)).to be(true) }
    %w[admin hr].each do |role|
      expect(described_class.new(create(:user, role:), :reference_data)).not_to be_create
      expect(described_class.new(create(:user, role:), :reference_data)).not_to be_manage
    end
  end

  describe 'ManagedScope' do
    it 'resolves to every row, retired ones too, for a developer' do
      create(:country, code: 'ref_policy_managed_off', active: false)

      resolved = described_class::ManagedScope.new(create(:user, role: 'developer'), Country.unscope(where: :active))

      expect(resolved.resolve.pluck(:code)).to include('ref_policy_managed_off')
    end

    it 'resolves to none for an admin' do
      expect(described_class::ManagedScope.new(create(:user, role: 'admin'), WorkflowStage).resolve.count).to eq(0)
    end
  end

  describe 'Scope' do
    it 'resolves to only active records for an authorized viewer' do
      create(:country, code: 'ref_policy_active', active: true)
      create(:country, code: 'ref_policy_inactive', active: false)
      mps = create(:user, role: 'mps')

      resolved = described_class::Scope.new(mps, Country).resolve

      expect(resolved.pluck(:code)).to include('ref_policy_active')
      expect(resolved.pluck(:code)).not_to include('ref_policy_inactive')
    end

    it 'resolves to none for an unauthorized viewer' do
      create(:country, code: 'ref_policy_scope_none', active: true)
      strip_permission!('finance', 'view_candidates')
      actor = create(:user, role: 'finance')

      expect(described_class::Scope.new(actor, Country).resolve.count).to eq(0)
    end
  end
end
