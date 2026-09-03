# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Payments::CorrectionService do
  before do
    ensure_canonical_workflow_stages!
    ensure_staff_authorization_reference_data!
  end

  let(:finance) { create(:user, role: 'finance') }
  let(:hr) { create(:user, role: 'hr') }

  def call(payment:, actor: finance, reason: 'Investigated and confirmed.', **overrides)
    described_class.call(
      actor:, payment:, reason:, request_id: SecureRandom.uuid,
      expected_updated_at: overrides[:expected_updated_at] || payment.reload.updated_at.iso8601,
      finding_id: overrides[:finding_id], field: overrides[:field], value: overrides[:value]
    )
  end

  it 'rejects an actor without manage_payments' do
    payment = create(:payment)

    expect { call(payment:, actor: hr, field: 'external_reference', value: 'EXT-1') }.to raise_error(ForbiddenError)
  end

  it 'rejects a blank reason' do
    payment = create(:payment)

    expect { call(payment:, reason: '  ', field: 'external_reference', value: 'EXT-1') }.to raise_error(ValidationError)
  end

  it 'rejects when neither a field nor a finding_id is supplied' do
    payment = create(:payment)

    expect { call(payment:) }.to raise_error(ValidationError)
  end

  describe 'stale-update protection' do
    it 'rejects a stale expected_updated_at' do
      payment = create(:payment)

      expect do
        call(payment:, expected_updated_at: 1.hour.ago.iso8601, field: 'external_reference', value: 'EXT-1')
      end.to raise_error(StalePaymentError)
    end

    it 'succeeds when expected_updated_at matches the current record' do
      payment = create(:payment, external_reference: nil)

      expect { call(payment:, field: 'external_reference', value: 'EXT-NEW') }.not_to raise_error
      expect(payment.reload.external_reference).to eq('EXT-NEW')
    end
  end

  describe 'external_reference correction' do
    it 'sets a missing external_reference' do
      payment = create(:payment, external_reference: nil)

      corrected = call(payment:, field: 'external_reference', value: 'EXT-123')

      expect(corrected.external_reference).to eq('EXT-123')
    end

    it 'rejects a blank value' do
      payment = create(:payment)

      expect { call(payment:, field: 'external_reference', value: '  ') }.to raise_error(ValidationError)
    end
  end

  describe 'paid_at correction' do
    it 'backfills a missing paid_at only when the payment is already paid' do
      payment = create(:payment, status_code: 'paid', paid_at: nil)
      timestamp = 1.day.ago.iso8601

      corrected = call(payment:, field: 'paid_at', value: timestamp)

      expect(corrected.paid_at.iso8601).to eq(Time.iso8601(timestamp).iso8601)
    end

    it 'refuses to set paid_at on a payment that is not paid' do
      payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)

      expect do
        call(payment:, field: 'paid_at', value: 1.day.ago.iso8601)
      end.to raise_error(PaymentCorrectionNotAllowedError)
    end

    it 'rejects a future paid_at' do
      payment = create(:payment, status_code: 'paid', paid_at: nil)

      expect { call(payment:, field: 'paid_at', value: 1.day.from_now.iso8601) }.to raise_error(ValidationError)
    end
  end

  describe 'status_code correction' do
    it 'allows closing an abandoned checkout to failed or cancelled' do
      payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)

      corrected = call(payment:, field: 'status_code', value: 'failed')

      expect(corrected.status_code).to eq('failed')
    end

    it 'refuses an arbitrary status transition with no evidence and no matching finding' do
      payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)

      expect do
        call(payment:, field: 'status_code', value: 'paid')
      end.to raise_error(PaymentCorrectionNotAllowedError)
    end

    it 'allows correcting to paid when a matching terminal_event_conflict finding and real provider evidence exist' do
      payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)
      create(:payment_event, payment:, event_type: 'payment_succeeded')
      run = create(:payment_reconciliation_run)
      finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                        finding_code: 'terminal_event_conflict')

      corrected = call(payment:, finding_id: finding.public_id, field: 'status_code', value: 'paid')

      expect(corrected.status_code).to eq('paid')
      expect(finding.reload).to be_resolved
    end

    it 'refuses to correct to paid via a finding_id that is not terminal_event_conflict, even with provider evidence' do
      payment = create(:payment, status_code: 'checkout_pending', paid_at: nil)
      create(:payment_event, payment:, event_type: 'payment_succeeded')
      run = create(:payment_reconciliation_run)
      finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                        finding_code: 'paid_at_missing')

      expect do
        call(payment:, finding_id: finding.public_id, field: 'status_code', value: 'paid')
      end.to raise_error(PaymentCorrectionNotAllowedError)
    end
  end

  describe 'finding resolution' do
    it 'resolves a finding with a note only, applying no field correction' do
      payment = create(:payment)
      run = create(:payment_reconciliation_run)
      finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                        finding_code: 'workflow_payment_mismatch')

      call(payment:, finding_id: finding.public_id, reason: 'Confirmed correct via manual audit, no action needed.')

      expect(finding.reload).to be_resolved
      expect(finding.resolution_note).to eq('Confirmed correct via manual audit, no action needed.')
    end

    it 'rejects an unknown finding_id' do
      payment = create(:payment)

      expect { call(payment:, finding_id: 'does-not-exist') }.to raise_error(ValidationError)
    end

    it 'rejects a finding_id that is already resolved' do
      payment = create(:payment)
      run = create(:payment_reconciliation_run)
      finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                        state_code: 'resolved', resolved_at: Time.current,
                                                        resolved_by: create(:user), resolution_note: 'x')

      expect { call(payment:, finding_id: finding.public_id) }.to raise_error(PaymentCorrectionNotAllowedError)
    end

    it 'rejects a finding_id belonging to a different payment' do
      payment = create(:payment)
      other_payment = create(:payment)
      run = create(:payment_reconciliation_run)
      finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment: other_payment)

      expect { call(payment:, finding_id: finding.public_id) }.to raise_error(ValidationError)
    end
  end

  describe 'audit trail' do
    it 'records a safe payment_corrected PaymentEvent and AuditEvent' do
      payment = create(:payment, external_reference: nil)

      expect do
        call(payment:, reason: 'Fixing a data-entry typo.', field: 'external_reference', value: 'EXT-999')
      end.to change(PaymentEvent, :count).by(1).and change(AuditEvent, :count).by(1)

      event = payment.payment_events.order(:occurred_at).last
      expect(event.event_source).to eq('admin_correction')
      expect(event.event_type).to eq('payment_corrected')
      expect(event.payload).to include('reason' => 'Fixing a data-entry typo.', 'field' => 'external_reference',
                                       'new_value' => 'EXT-999')

      audit = AuditEvent.where(action_code: 'payment_corrected').last
      expect(audit.entity_type).to eq('Payment')
      expect(audit.entity_id).to eq(payment.id)
    end
  end

  it 'rejects an unsupported field' do
    payment = create(:payment)

    expect { call(payment:, field: 'amount', value: '5000') }.to raise_error(PaymentCorrectionNotAllowedError)
  end
end
