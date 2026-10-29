# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::DeliveryJob do
  include ActiveJob::TestHelper

  let(:assignment) { create(:candidate_assignment) }
  let(:delivery) do
    CandidateSmsDelivery.create!(
      candidate: assignment.candidate, candidate_assignment: assignment, message_code: 'visa_issued',
      dedupe_key: 'visa_decision:1', locale: 'en', variables: { 'name' => 'Daim Javed' }
    )
  end

  it 'sends the delivery' do
    allow(Sms::SendMessage).to receive(:call)
      .and_return(Sms::DeliveryResult.new(success: true, provider_reference: '1'))

    described_class.perform_now(candidate_sms_delivery_id: delivery.id)

    expect(delivery.reload.status).to eq('sent')
  end

  it 'retries a network failure and marks the delivery failed once the retries run out' do
    allow(Sms::SendMessage).to receive(:call).and_return(Sms::DeliveryResult.new(success: false, error_code: 'timeout'))

    perform_enqueued_jobs { described_class.perform_later(candidate_sms_delivery_id: delivery.id) }

    expect(Sms::SendMessage).to have_received(:call).exactly(5).times
    expect(delivery.reload).to have_attributes(status: 'failed', error_code: 'timeout')
  end
end
