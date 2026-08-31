# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidatePolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  let(:candidate) { create(:candidate) }

  def strip_permission!(role_code, permission_code)
    RolePermission.joins(:role, :permission)
                  .find_by!(roles: { code: role_code }, permissions: { code: permission_code })
                  .destroy!
  end

  it 'allows show for view/manage-candidates roles, and create/update only for manage-candidates roles' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')
    mps = create(:user, role: 'mps')
    finance = create(:user, role: 'finance')

    expect(described_class.new(admin, candidate).show?).to be(true)
    expect(described_class.new(admin, candidate).create?).to be(true)
    expect(described_class.new(admin, candidate).update?).to be(true)

    expect(described_class.new(hr, candidate).show?).to be(true)
    expect(described_class.new(hr, candidate).create?).to be(true)
    expect(described_class.new(hr, candidate).update?).to be(true)

    expect(described_class.new(mps, candidate).show?).to be(true)
    expect(described_class.new(mps, candidate).create?).to be(false)
    expect(described_class.new(mps, candidate).update?).to be(false)

    expect(described_class.new(finance, candidate).show?).to be(true)
    expect(described_class.new(finance, candidate).create?).to be(false)
    expect(described_class.new(finance, candidate).update?).to be(false)
  end

  it 'denies everything for a role with neither view_candidates nor manage_candidates' do
    strip_permission!('finance', 'view_candidates')
    actor = create(:user, role: 'finance')

    expect(described_class.new(actor, candidate).show?).to be(false)
    expect(described_class.new(actor, candidate).create?).to be(false)
    expect(described_class.new(actor, candidate).update?).to be(false)
  end

  describe 'Scope' do
    it 'resolves to all candidates for an authorized viewer, and none for an unauthorized one' do
      create_list(:candidate, 2)
      mps = create(:user, role: 'mps')
      strip_permission!('finance', 'view_candidates')
      unauthorized = create(:user, role: 'finance')

      expect(described_class::Scope.new(mps, Candidate).resolve.count).to eq(2)
      expect(described_class::Scope.new(unauthorized, Candidate).resolve.count).to eq(0)
    end
  end
end
