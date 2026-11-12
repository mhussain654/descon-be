# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::IssueFeeVoucherJob do
  include ActiveJob::TestHelper

  it 'issues the fee voucher for the assignment and stage entry it was queued for' do
    allow(Payments::IssueFeeVoucherService).to receive(:call)

    described_class.perform_now(candidate_assignment_id: 7, history_entry_id: 41)

    expect(Payments::IssueFeeVoucherService).to have_received(:call)
      .with(candidate_assignment_id: 7, history_entry_id: 41)
  end

  it 'gives up after five tries, logging which assignment it was' do
    allow(Payments::IssueFeeVoucherService).to receive(:call).and_raise(PaymentCheckoutUnavailableError)
    allow(Rails.logger).to receive(:warn)

    perform_enqueued_jobs { described_class.perform_later(candidate_assignment_id: 7, history_entry_id: 41) }

    expect(Payments::IssueFeeVoucherService).to have_received(:call).exactly(5).times
    expect(Rails.logger).to have_received(:warn).with(include('candidate_assignment_id=7'))
  end

  it 'retries later when KuickPay is unavailable' do
    allow(Payments::IssueFeeVoucherService).to receive(:call).and_raise(PaymentCheckoutUnavailableError)

    expect { described_class.perform_now(candidate_assignment_id: 7, history_entry_id: 41) }
      .to have_enqueued_job(described_class).with(candidate_assignment_id: 7, history_entry_id: 41)
  end
end
