# frozen_string_literal: true

module Payments
  class ReconciliationService < ApplicationService
    FINDINGS = {
      'paid_at_missing' => :paid_at_missing?,
      'external_reference_missing' => :external_reference_missing?,
      'duplicate_external_reference' => :duplicate_external_reference?,
      'workflow_payment_mismatch' => :workflow_mismatch?,
      'terminal_event_conflict' => :terminal_event_conflict?
    }.freeze

    def initialize(run_date: Date.current, actor: nil)
      @run_date = run_date
      @actor = actor
    end

    def call
      PaymentReconciliationRun.transaction do
        run = find_or_create_run
        return run if run.status_code == 'completed'

        reconcile!(run)
        run
      end
    end

    private

    def find_or_create_run
      PaymentReconciliationRun.lock.find_or_create_by!(run_date: @run_date) do |record|
        record.initiated_by = @actor
        record.started_at = Time.current
      end
    end

    # Re-running reconciliation for a `run_date` that already has resolved
    # findings must not resurrect them as `open` -- only `open` findings are
    # cleared and recomputed here; a finding a staff member has already
    # investigated and resolved (Admin::Payments::CorrectionService) survives
    # across same-day re-runs.
    def reconcile!(run)
      run.payment_reconciliation_findings.open_state.delete_all
      Payment.find_each { |payment| record_findings(run, payment) }
      run.update!(status_code: 'completed', completed_at: Time.current, summary: summary_for(run))
    end

    def record_findings(run, payment)
      findings_for(payment).each { |code| create_finding!(run, payment, code) }
    end

    def findings_for(payment)
      FINDINGS.filter_map { |code, predicate| code if send(predicate, payment) }
    end

    def paid_at_missing?(payment) = payment.paid? && payment.paid_at.blank?
    def external_reference_missing?(payment) = payment.paid? && payment.external_reference.blank?

    def duplicate_external_reference?(payment)
      payment.external_reference.present? && Payment.where(external_reference: payment.external_reference)
                                                    .where.not(id: payment.id).exists?
    end

    def workflow_mismatch?(payment)
      payment.paid? && payment.candidate_assignment.current_workflow_stage.code != 'fee_paid'
    end

    def terminal_event_conflict?(payment)
      !payment.paid? && payment.payment_events.exists?(event_type: 'payment_succeeded')
    end

    def create_finding!(run, payment, code)
      return if run.payment_reconciliation_findings.exists?(payment:, finding_code: code)

      run.payment_reconciliation_findings.create!(
        payment:,
        finding_code: code,
        details: { payment_public_id: payment.public_id }
      )
    end

    def summary_for(run)
      { findings: run.payment_reconciliation_findings.count, payments_checked: Payment.count }
    end
  end
end
