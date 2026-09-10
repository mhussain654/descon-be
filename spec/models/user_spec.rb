# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it do
    expect(user).to belong_to(:staff_role)
      .class_name('Role')
      .with_foreign_key(:role)
      .with_primary_key(:code)
      .optional
  end

  it { is_expected.to have_many(:sessions).dependent(:destroy) }
  it { is_expected.to validate_uniqueness_of(:public_id) }

  # Not :nullify -- both associations are ImmutableRecord (append-only), and
  # :nullify is a bulk UPDATE that bypasses ImmutableRecord's before_update
  # guard entirely, silently erasing audit-trail attribution.
  it {
    expect(user).to have_many(:acted_stage_histories).class_name('CandidateStageHistory')
                                                     .dependent(:restrict_with_exception)
  }

  it { is_expected.to have_many(:audit_events).dependent(:restrict_with_exception) }

  it 'refuses to destroy a user with recorded audit events/stage-history actions, instead of silently erasing them' do
    actor = create(:user)
    candidate = create(:candidate)
    AuditEvent.create!(actor:, entity_type: 'Candidate', entity_id: candidate.id, action_code: 'candidate_created',
                       occurred_at: Time.current)

    expect { actor.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(AuditEvent.where(actor:)).to exist
  end

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
    role = Role.find_or_initialize_by(code: 'admin')
    role.system_defined = true
    role.active = true
    role.save! if role.new_record?

    permission = Permission.find_or_initialize_by(code: 'manage_candidates')
    permission.system_defined = true
    permission.active = true
    permission.save! if permission.new_record?

    RolePermission.find_or_create_by!(role:, permission:)
    user = create(:user, role: role.code)

    expect(user.admin?).to be(true)
    expect(user.permission?('manage_candidates')).to be(true)
    expect(user.permission?('unknown_permission')).to be(false)
  end

  it 'recognizes scoped staff roles' do
    user.role = 'finance'

    expect(user.finance?).to be(true)
    expect(user.staff?).to be(true)
    expect(user.management?).to be(false)
  end

  it 'syncs staff_state from the active flag when callers suspend a user directly' do
    user.active = false
    user.validate

    expect(user.staff_state).to eq('suspended')
  end

  it 'syncs the active flag from staff_state for invited users' do
    user.staff_state = 'invited'
    user.validate

    expect(user.active).to be(false)
  end
end
