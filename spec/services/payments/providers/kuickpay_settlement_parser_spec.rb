# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpaySettlementParser do
  def row(overrides = {})
    {
      'consumer_Number' => '10420261000061895', 'registrationNumber' => '5675',
      'transaction_Date_Time' => '2026-10-27T00:00:00', 'settlement_Date_Time' => nil, 'amountTransaction' => 100.0,
      'authID' => '819175', 'bank' => 'KPY', 'isSettled' => false, 'tranTime' => '091602', 'fee' => 50.0,
      'amountAfterFee' => 50.0
    }.merge(overrides)
  end

  it 'reads a payment KuickPay has not settled yet, as a paid voucher' do
    expect(described_class.call(row)).to have_attributes(
      consumer_number: '10420261000061895', registration_number: '5675', amount: BigDecimal('100'),
      auth_id: '819175', bank: 'KPY'
    )
  end

  it 'takes the paid time from the transaction date and tranTime, in UTC, until KuickPay settles it' do
    expect(described_class.call(row).paid_at).to eq(Time.find_zone('UTC').parse('2026-10-27 09:16:02'))
  end

  it 'prefers the settlement time once there is one' do
    settled = row('settlement_Date_Time' => '2026-10-28T10:00:05', 'isSettled' => true)

    expect(described_class.call(settled).paid_at).to eq(Time.find_zone('UTC').parse('2026-10-28 10:00:05'))
  end

  it 'falls back to midnight when tranTime is missing, and to no time when the date is unreadable' do
    expect(described_class.call(row('tranTime' => nil)).paid_at)
      .to eq(Time.find_zone('UTC').parse('2026-10-27 00:00:00'))
    expect(described_class.call(row('transaction_Date_Time' => 'garbage', 'tranTime' => '999999')).paid_at).to be_nil
  end

  it 'skips a row with no voucher number or an unreadable amount' do
    expect(described_class.call(row('consumer_Number' => ''))).to be_nil
    expect(described_class.call(row('amountTransaction' => 'abc'))).to be_nil
  end
end
