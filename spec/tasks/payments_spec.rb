# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'payments:kuickpay:verify_status rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['payments:kuickpay:verify_status'].reenable
  end

  def status_response(body: { 'responseData' => { 'status' => 'success', 'responseCode' => '00' } })
    Payments::Providers::StatusCheckResponse.new(http_status: 200, body:)
  end

  it 'aborts with no public_id given' do
    expect { Rake::Task['payments:kuickpay:verify_status'].invoke }.to raise_error(SystemExit)
  end

  it 'aborts when no payment exists with the given public_id' do
    expect do
      Rake::Task['payments:kuickpay:verify_status'].invoke('does-not-exist')
    end.to raise_error(SystemExit).and output(/No payment found/).to_stderr
  end

  it 'aborts when the payment is not a KuickPay payment' do
    payment = create(:payment, provider_code: 'other_provider')

    expect do
      Rake::Task['payments:kuickpay:verify_status'].invoke(payment.public_id)
    end.to raise_error(SystemExit).and output(/not a KuickPay payment/).to_stderr
  end

  it 'invokes the verify status service and prints the request outcome and resulting payment status' do
    payment = create(:payment, provider_code: 'kuickpay', status_code: 'checkout_pending')
    allow(Payments::VerifyPaymentStatusService).to receive(:call)
      .with(payment:, request_id: anything)
      .and_return(status_response)

    expected_output = /HTTP status: 200.*Response body:.*status_code is now: checkout_pending/m
    expect do
      Rake::Task['payments:kuickpay:verify_status'].invoke(payment.public_id)
    end.to output(expected_output).to_stdout

    expect(Payments::VerifyPaymentStatusService).to have_received(:call).with(payment:, request_id: anything)
  end

  it 'aborts with a clear message when the provider call itself fails' do
    payment = create(:payment, provider_code: 'kuickpay')
    allow(Payments::VerifyPaymentStatusService).to receive(:call).and_raise(PaymentCheckoutUnavailableError)

    expect do
      Rake::Task['payments:kuickpay:verify_status'].invoke(payment.public_id)
    end.to raise_error(SystemExit).and output(/Failed: PaymentCheckoutUnavailableError/).to_stderr
  end
end
