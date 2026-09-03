# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentReconciliationFinding, type: :model do
  it 'assigns a public_id on create' do
    finding = create(:payment_reconciliation_finding)

    expect(finding.public_id).to be_present
  end

  it 'rejects a state_code outside STATES' do
    finding = build(:payment_reconciliation_finding, state_code: 'bogus')

    expect(finding).not_to be_valid
    expect(finding.errors[:state_code]).to be_present
  end

  it 'requires finding_code to be unique per run and payment' do
    run = create(:payment_reconciliation_run)
    payment = create(:payment)
    create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:, finding_code: 'paid_at_missing')
    duplicate = build(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                       finding_code: 'paid_at_missing')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:finding_code]).to be_present
  end

  describe '#resolve!' do
    it 'marks the finding resolved with a resolver, timestamp and note' do
      finding = create(:payment_reconciliation_finding)
      resolver = create(:user, role: 'finance')

      finding.resolve!(by: resolver, note: 'Verified against the provider dashboard.')

      expect(finding.reload).to be_resolved
      expect(finding.resolved_by).to eq(resolver)
      expect(finding.resolved_at).to be_present
      expect(finding.resolution_note).to eq('Verified against the provider dashboard.')
    end

    it 'requires a resolution_note' do
      finding = create(:payment_reconciliation_finding)

      expect { finding.resolve!(by: create(:user), note: '') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.open_state' do
    it 'returns only findings whose state_code is open' do
      open_finding = create(:payment_reconciliation_finding, state_code: 'open')
      resolved_finding = create(:payment_reconciliation_finding, state_code: 'resolved', resolved_at: Time.current,
                                                                 resolved_by: create(:user), resolution_note: 'ok')

      expect(described_class.open_state).to include(open_finding)
      expect(described_class.open_state).not_to include(resolved_finding)
    end
  end
end
