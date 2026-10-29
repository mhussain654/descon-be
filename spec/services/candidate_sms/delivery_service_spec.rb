# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::DeliveryService do
  let(:candidate) { create(:candidate, full_name: 'Daim Javed', preferred_locale: 'ur') }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:delivery) do
    CandidateSmsDelivery.create!(
      candidate:, candidate_assignment: assignment, message_code: 'qvc_appointment', dedupe_key: 'qvc_appointment:1',
      locale: 'ur', variables: { 'name' => 'Daim Javed', 'date' => '04-11-2026' }
    )
  end

  def deliver = described_class.call(candidate_sms_delivery_id: delivery.id)

  def stub_send(result)
    allow(Sms::SendMessage).to receive(:call).and_return(result)
  end

  it 'sends the message’s template in the candidate’s language and records it as sent' do
    stub_send(Sms::DeliveryResult.new(success: true, provider_reference: '29346'))

    deliver

    expect(Sms::SendMessage).to have_received(:call).with(
      to: candidate.mobile_number, variables: { 'name' => 'Daim Javed', 'date' => '04-11-2026' },
      template: 'qvc_appointment', locale: 'ur', body: include('04-11-2026')
    )
    expect(delivery.reload).to have_attributes(status: 'sent', provider_reference: '29346', sent_at: be_present)
  end

  it 'never sends a delivery that is no longer pending' do
    delivery.update!(status: 'sent')
    allow(Sms::SendMessage).to receive(:call)

    deliver

    expect(Sms::SendMessage).not_to have_received(:call)
  end

  it 'skips a message whose template is not set up yet' do
    stub_send(Sms::DeliveryResult.new(success: false, error_code: 'not_configured'))

    deliver

    expect(delivery.reload).to have_attributes(status: 'skipped', error_code: 'not_configured')
  end

  it 'raises a retryable error for a network-level failure and leaves the delivery pending' do
    stub_send(Sms::DeliveryResult.new(success: false, error_code: 'timeout'))

    expect { deliver }.to raise_error(described_class::RetryableError, 'timeout')
    expect(delivery.reload.status).to eq('pending')
  end

  it 'marks a refused message as failed' do
    stub_send(Sms::DeliveryResult.new(success: false, error_code: 'invalid_recipient'))

    deliver

    expect(delivery.reload).to have_attributes(status: 'failed', error_code: 'invalid_recipient')
  end

  it 'skips a candidate who became inactive after it was queued' do
    delivery
    candidate.update!(active: false)
    allow(Sms::SendMessage).to receive(:call)

    deliver

    expect(Sms::SendMessage).not_to have_received(:call)
    expect(delivery.reload).to have_attributes(status: 'skipped', error_code: 'candidate_inactive')
  end
end
