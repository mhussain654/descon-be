# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::PaymentStateApplier do
  before do
    ensure_canonical_workflow_stages!
  end

  def stage_for(code)
    WorkflowStage.find_by!(code:)
  end

  def notification(status:, transaction_id:, response_code: '00', occurred_at: default_occurred_at)
    Payments::Providers::Notification.new(
      **notification_attributes(status:, transaction_id:, response_code:, occurred_at:)
    )
  end

  def notification_attributes(status:, transaction_id:, response_code:, occurred_at:)
    notification_identity.merge(
      provider_transaction_id: transaction_id,
      provider_status_code: status,
      provider_response_code: response_code,
      occurred_at:
    )
  end

  def notification_identity
    {
      provider_code: 'mock_hosted_checkout',
      event_source: 'callback',
      event_key: SecureRandom.hex(8),
      provider_order_id: 'PAY-ORDER-1',
      amount: BigDecimal('1500.0'),
      currency_code: 'PKR',
      payload: {}
    }
  end

  def default_occurred_at
    Time.zone.parse('2026-08-31T09:05:00Z')
  end

  it 'marks a payment paid and advances verified candidates through fee_pending to fee_paid' do
    candidate = create(:candidate, status_code: 'verified')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('verified'))
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'checkout_pending',
      amount: BigDecimal('1500.0'),
      currency_code: 'PKR'
    )

    allow(Payments::AuditRecorder).to receive(:call)
    allow(CandidateWorkflows::TransitionService).to receive(:call) do |candidate:, to_stage_code:, **|
      destination = WorkflowStage.find_by!(code: to_stage_code)
      assignment.update!(current_workflow_stage: destination, updated_at: Time.current)
      candidate.update!(status_code: destination.code)
    end

    described_class.call(
      payment:,
      assignment:,
      candidate:,
      notification: notification(status: 'SUCCESS', transaction_id: 'TXN-1'),
      request_id: 'req-1'
    )

    expect(payment.reload.status_code).to eq('paid')
    expect(payment.external_reference).to eq('TXN-1')
    expect(payment.paid_at).to eq(Time.zone.parse('2026-08-31T09:05:00Z'))
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
    expect(candidate.reload.status_code).to eq('fee_paid')
    expect(Payments::AuditRecorder).to have_received(:call).with(hash_including(action: :paid))
    expect(CandidateWorkflows::TransitionService)
      .to have_received(:call).with(hash_including(to_stage_code: 'fee_pending'))
    expect(CandidateWorkflows::TransitionService)
      .to have_received(:call).with(hash_including(to_stage_code: 'fee_paid'))
  end

  it 'marks a checkout as cancelled without advancing workflow' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    payment = create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending')

    allow(Payments::AuditRecorder).to receive(:call)
    allow(CandidateWorkflows::TransitionService).to receive(:call)

    described_class.call(
      payment:,
      assignment:,
      candidate:,
      notification: notification(status: 'CANCELLED', transaction_id: 'TXN-2', response_code: '05'),
      request_id: 'req-2'
    )

    expect(payment.reload.status_code).to eq('cancelled')
    expect(payment.external_reference).to be_nil
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_pending')
    expect(Payments::AuditRecorder).to have_received(:call).with(hash_including(action: :cancelled))
    expect(CandidateWorkflows::TransitionService).not_to have_received(:call)
  end

  it 'ignores non-success notifications once a payment is already paid' do
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      external_reference: 'TXN-ORIGINAL',
      provider_transaction_id: 'TXN-ORIGINAL',
      paid_at: Time.zone.parse('2026-08-31T09:00:00Z')
    )

    allow(Payments::AuditRecorder).to receive(:call)
    allow(CandidateWorkflows::TransitionService).to receive(:call)

    described_class.call(
      payment:,
      assignment:,
      candidate:,
      notification: notification(status: 'FAILED', transaction_id: 'TXN-3', response_code: '09'),
      request_id: 'req-3'
    )

    expect(payment.reload.status_code).to eq('paid')
    expect(payment.external_reference).to eq('TXN-ORIGINAL')
    expect(Payments::AuditRecorder).not_to have_received(:call)
    expect(CandidateWorkflows::TransitionService).not_to have_received(:call)
  end
end
