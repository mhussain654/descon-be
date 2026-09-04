# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentReconciliationRun, type: :model do
  it 'is valid with a unique run_date and a state from STATES' do
    run = build(:payment_reconciliation_run, run_date: Date.current)

    expect(run).to be_valid
  end

  it 'requires run_date to be unique' do
    create(:payment_reconciliation_run, run_date: Date.current)
    duplicate = build(:payment_reconciliation_run, run_date: Date.current)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:run_date]).to be_present
  end

  it 'rejects a status_code outside STATES' do
    run = build(:payment_reconciliation_run, status_code: 'bogus')

    expect(run).not_to be_valid
    expect(run.errors[:status_code]).to be_present
  end

  it 'associates findings and restricts destroy while findings exist' do
    run = create(:payment_reconciliation_run)
    create(:payment_reconciliation_finding, payment_reconciliation_run: run)

    expect { run.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
