# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::VerifyPaymentStatusService do
  before do
    ensure_canonical_workflow_stages!
    allow(Payments::ProviderRegistry).to receive(:fetch).with('kuickpay').and_return(provider)
  end

  let(:candidate) { create(:candidate, status_code: 'fee_pending') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'))
  end
  let(:payment) do
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'checkout_pending',
      amount: BigDecimal('1500.0'),
      currency_code: 'PKR',
      provider_code: 'kuickpay',
      provider_order_id: 'PAY-ORDER-1',
      provider_amount_payable: '1500.00',
      provider_request_timestamp: '2026-08-31T09:00:00Z',
      provider_request_signature: 'sig=='
    )
  end
  let(:provider) { instance_double(Payments::Providers::KuickpayHostedCheckoutAdapter) }

  def status_response(body:, http_status: 200)
    Payments::Providers::StatusCheckResponse.new(http_status:, body:)
  end

  it 'records a PaymentEvent with the raw response even when it cannot be confidently interpreted' do
    allow(provider).to receive(:verify_status).with(payment:)
                                              .and_return(status_response(body: { 'message' => 'Session not found' }))

    expect do
      described_class.call(payment:, request_id: 'req-1')
    end.to change(PaymentEvent, :count).by(1)

    event = PaymentEvent.last
    expect(event.event_source).to eq('status_check')
    expect(event.event_type).to eq('status_checked')
    expect(event.provider_code).to eq('kuickpay')
    expect(event.provider_order_id).to eq('PAY-ORDER-1')
    expect(event.payload).to eq('http_status' => 200, 'body' => { 'message' => 'Session not found' })
    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  # Confirmed against the real sandbox (2026-10-01): {"responseCode":"00",
  # "status":true,"sessionID":"...","gatewayResponse":{"paymentStatus":"00",
  # "paymentID":"..."}} -- no responseData wrapper, unlike Create Session.
  def real_success_response_body(payment_id: 'TXN-9')
    {
      'responseCode' => '00',
      'responseDescription' => 'Session found',
      'status' => true,
      'orderID' => 'PAY-ORDER-1',
      'sessionID' => 'session-1',
      'gatewayResponse' => { 'paymentStatus' => '00', 'paymentID' => payment_id }
    }
  end

  it 'applies a success outcome from the real confirmed gatewayResponse shape, not the top-level envelope status' do
    allow(provider).to receive(:verify_status).with(payment:)
                                              .and_return(status_response(body: real_success_response_body))
    allow(CandidateWorkflows::TransitionService).to receive(:call) do |candidate:, to_stage_code:, **|
      destination = WorkflowStage.find_by!(code: to_stage_code)
      assignment.update!(current_workflow_stage: destination, updated_at: Time.current)
      candidate.update!(status_code: destination.code)
    end

    described_class.call(payment:, request_id: 'req-1')

    payment.reload
    expect(payment.status_code).to eq('paid')
    expect(payment.provider_transaction_id).to eq('TXN-9')
    expect(payment.provider_status_code).to eq('SUCCESS')
    expect(payment.provider_response_code).to eq('00')
  end

  it 'does not misread the top-level envelope status ("session found") as the payment outcome itself' do
    # Regression test for a real bug: this response is genuinely a success
    # (gatewayResponse.paymentStatus == '00'), but naively reading the
    # top-level `status: true` as the outcome stringifies to "TRUE", which
    # matches neither SUCCESS nor CANCELLED in Notification, mis-marking a
    # real successful payment as failed.
    allow(provider).to receive(:verify_status).with(payment:)
                                              .and_return(status_response(body: real_success_response_body))
    allow(CandidateWorkflows::TransitionService).to receive(:call) do |candidate:, to_stage_code:, **|
      destination = WorkflowStage.find_by!(code: to_stage_code)
      assignment.update!(current_workflow_stage: destination, updated_at: Time.current)
      candidate.update!(status_code: destination.code)
    end

    described_class.call(payment:, request_id: 'req-1')

    expect(payment.reload.status_code).not_to eq('failed')
  end

  it 'leaves the payment untouched for the real confirmed "session not found" shape' do
    allow(provider).to receive(:verify_status).with(payment:).and_return(
      status_response(body: { 'responseCode' => '01', 'responseDescription' => 'Session not found',
                              'status' => 'failure' })
    )

    described_class.call(payment:, request_id: 'req-1')

    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'leaves the payment untouched when the session was found but gatewayResponse is missing or unrecognized' do
    allow(provider).to receive(:verify_status).with(payment:).and_return(
      status_response(body: { 'responseCode' => '00', 'status' => true, 'sessionID' => 'session-1' })
    )

    described_class.call(payment:, request_id: 'req-1')

    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'leaves the payment untouched when the response body is not a Hash' do
    allow(provider).to receive(:verify_status).with(payment:).and_return(status_response(body: 'not-json'))

    described_class.call(payment:, request_id: 'req-1')

    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'never applies a notification once the payment is already paid, even if the response says success again' do
    payment.update!(status_code: 'paid', external_reference: 'TXN-9', provider_status_code: 'SUCCESS',
                    paid_at: Time.current)
    allow(provider).to receive(:verify_status).with(payment:)
                                              .and_return(status_response(body: real_success_response_body))

    expect { described_class.call(payment:, request_id: 'req-1') }.not_to raise_error
    expect(payment.reload.status_code).to eq('paid')
  end

  it 'propagates a provider failure rather than swallowing it, recording no PaymentEvent' do
    allow(provider).to receive(:verify_status).with(payment:).and_raise(PaymentCheckoutUnavailableError)

    expect { described_class.call(payment:, request_id: 'req-1') }.to raise_error(PaymentCheckoutUnavailableError)
    expect(PaymentEvent.count).to eq(0)
  end
end
