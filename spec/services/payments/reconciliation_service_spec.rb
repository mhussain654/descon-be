# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ReconciliationService do
  def stage_for(code) = WorkflowStage.find_by!(code:)

  # A payment whose own paid/workflow status is internally consistent (paid,
  # assignment already at fee_paid, has an external_reference) except for
  # whatever `overrides` deliberately unsettles -- keeps each example
  # isolated to the one finding it's testing for.
  def consistent_paid_payment(**overrides)
    assignment = overrides.delete(:candidate_assignment) || create(:candidate_assignment,
                                                                   current_workflow_stage: stage_for('fee_paid'))
    create(:payment, candidate_assignment: assignment, external_reference: "EXT-#{SecureRandom.hex(4).upcase}",
                     **overrides)
  end

  before { ensure_canonical_workflow_stages! }

  it 'creates one run per run_date and flags a payment missing paid_at' do
    payment = consistent_paid_payment(paid_at: nil)

    run = described_class.call(run_date: Date.current)

    expect(run.status_code).to eq('completed')
    expect(run.payment_reconciliation_findings.pluck(:payment_id,
                                                     :finding_code)).to eq([[payment.id, 'paid_at_missing']])
  end

  it 'flags a paid payment missing an external_reference' do
    consistent_paid_payment(external_reference: nil)

    run = described_class.call(run_date: Date.current)

    expect(run.payment_reconciliation_findings.pluck(:finding_code)).to eq(['external_reference_missing'])
  end

  it 'flags two payments sharing the same external_reference as duplicates' do
    # The model itself enforces external_reference uniqueness with a unique
    # partial index, so a genuine duplicate can only exist as leftover/
    # pre-constraint data -- exactly the kind of thing reconciliation exists
    # to catch. Drop the index for this one example to reproduce that state;
    # Postgres DDL is transactional, so RSpec's transaction rollback restores
    # it automatically once the example finishes -- no manual recreation.
    ActiveRecord::Base.connection.execute('DROP INDEX index_payments_on_external_reference')
    first = consistent_paid_payment
    second = consistent_paid_payment
    # update_column deliberately skips the model's own uniqueness validation
    # -- that's the point, see above.
    second.update_column(:external_reference, first.external_reference) # rubocop:disable Rails/SkipsModelValidations

    run = described_class.call(run_date: Date.current)

    expect(run.payment_reconciliation_findings.where(finding_code: 'duplicate_external_reference').count).to eq(2)
  end

  it 'flags a paid payment whose assignment never advanced to fee_paid' do
    assignment = create(:candidate_assignment, current_workflow_stage: stage_for('verified'))
    consistent_paid_payment(candidate_assignment: assignment)

    run = described_class.call(run_date: Date.current)

    expect(run.payment_reconciliation_findings.pluck(:finding_code)).to include('workflow_payment_mismatch')
  end

  it 'flags a non-paid payment that already has a payment_succeeded event on record' do
    payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)
    create(:payment_event, payment:, event_type: 'payment_succeeded')

    run = described_class.call(run_date: Date.current)

    expect(run.payment_reconciliation_findings.pluck(:finding_code)).to include('terminal_event_conflict')
  end

  it 'does not flag a clean, fully-paid, workflow-consistent payment' do
    consistent_paid_payment

    run = described_class.call(run_date: Date.current)

    expect(run.payment_reconciliation_findings).to be_empty
  end

  it 'reuses the existing run for the same run_date instead of creating a second one' do
    described_class.call(run_date: Date.current)

    expect { described_class.call(run_date: Date.current) }.not_to change(PaymentReconciliationRun, :count)
  end

  it 'is a no-op once a run for that date is already completed, even if new problem payments appear afterwards' do
    consistent_paid_payment(paid_at: nil)
    first_run = described_class.call(run_date: Date.current)
    expect(first_run.payment_reconciliation_findings.count).to eq(1)

    consistent_paid_payment(paid_at: nil)
    described_class.call(run_date: Date.current)

    expect(first_run.reload.payment_reconciliation_findings.count).to eq(1)
  end

  it 'does not resurrect a finding a staff member already resolved, on a same-day re-run against a reopened run' do
    payment = consistent_paid_payment(paid_at: nil)
    run = described_class.call(run_date: Date.current)
    finding = run.payment_reconciliation_findings.find_by!(payment:, finding_code: 'paid_at_missing')
    finding.resolve!(by: create(:user, role: 'finance'), note: 'Backfilled paid_at manually.')
    run.update!(status_code: 'processing')

    described_class.call(run_date: Date.current)

    expect(finding.reload).to be_resolved
    expect(run.payment_reconciliation_findings.where(payment:, finding_code: 'paid_at_missing').count).to eq(1)
  end
end
