# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateBankDetailPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  it 'grants masked access to view_payments roles and unmasked/proof access to manage_payments roles' do
    bank_detail = create(:candidate_bank_detail)

    admin_policy = described_class.new(create(:user, role: 'admin'), bank_detail)
    finance_policy = described_class.new(create(:user, role: 'finance'), bank_detail)
    management_policy = described_class.new(create(:user, role: 'management'), bank_detail)
    hr_policy = described_class.new(create(:user, role: 'hr'), bank_detail)

    expect(admin_policy.show?).to be(true)
    expect(admin_policy.access_proof?).to be(true)
    expect(admin_policy.view_unmasked?).to be(true)

    expect(finance_policy.show?).to be(true)
    expect(finance_policy.access_proof?).to be(true)
    expect(finance_policy.view_unmasked?).to be(true)

    expect(management_policy.show?).to be(true)
    expect(management_policy.access_proof?).to be(false)
    expect(management_policy.view_unmasked?).to be(false)

    expect(hr_policy.show?).to be(false)
    expect(hr_policy.access_proof?).to be(false)
  end

  it 'scopes only current bank-detail versions for authorized staff' do
    current_record = create(:candidate_bank_detail)
    create(:candidate_bank_detail, superseded_at: Time.current)
    actor = create(:user, role: 'finance')

    scoped_records = described_class::Scope.new(actor, CandidateBankDetail.all).resolve

    expect(scoped_records).to include(current_record)
    expect(scoped_records.where.not(superseded_at: nil)).to be_empty
  end
end
