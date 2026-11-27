# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'payments:kuickpay:reissue_voucher rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before { Rake::Task['payments:kuickpay:reissue_voucher'].reenable }

  let(:task) { Rake::Task['payments:kuickpay:reissue_voucher'] }

  it 'aborts with no Kuickpay ID given, or one that matches no voucher' do
    expect { task.invoke }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    task.reenable
    expect { task.invoke('0000899999') }.to raise_error(SystemExit).and output(/No unpaid KuickPay voucher/).to_stderr
  end

  it 'prints the old and new Kuickpay IDs' do
    payment = create(:payment, provider_code: 'kuickpay_voucher', voucher_number: '0000826110503906',
                               status_code: 'checkout_pending')
    new_payment = build_stubbed(:payment, voucher_number: '0000800000099', voucher_due_on: Date.new(2026, 12, 11),
                                          checkout_expires_at: Time.zone.parse('2026-12-13 18:59:59'))
    result = Payments::ReissueVoucherService::Result.new(old_payment: payment, new_payment:, sms_sent: true)
    allow(Payments::ReissueVoucherService).to receive(:call).with(payment:).and_return(result)

    expect do
      task.invoke('0000826110503906')
    end.to output(/New Kuickpay ID: 0000800000099 \(due 2026-12-11, payable until 2026-12-13\)/).to_stdout
  end

  it 'aborts for a voucher that is already paid, and with the reason when it cannot be replaced' do
    create(:payment, provider_code: 'kuickpay_voucher', voucher_number: '0000826110503906', status_code: 'paid')
    expect do
      task.invoke('0000826110503906')
    end.to raise_error(SystemExit).and output(/No unpaid KuickPay voucher/).to_stderr

    task.reenable
    pending_payment = create(:payment, provider_code: 'kuickpay_voucher', voucher_number: '0000826110503907',
                                       status_code: 'checkout_pending')
    allow(Payments::ReissueVoucherService).to receive(:call).with(payment: pending_payment)
                                                            .and_raise(PaymentCheckoutUnavailableError)
    expect { task.invoke('0000826110503907') }.to raise_error(SystemExit).and output(/Failed/).to_stderr
  end
end
