# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppFeatureSetting do
  it 'starts with every switch on' do
    setting = described_class.current

    expect(described_class::SWITCHES.map { |switch| setting.public_send(:"#{switch}_enabled") }).to all(be(true))
    expect(setting.disabled_sms_messages).to eq([])
  end

  it 'keeps a single row' do
    first = described_class.current

    expect(described_class.current).to eq(first)
    expect(described_class.count).to eq(1)
  end

  it 'reads one switch by name and refuses an unknown one' do
    described_class.current.update!(voucher_payment_enabled: false)

    expect(described_class.enabled?(:voucher_payment)).to be(false)
    expect(described_class.enabled?('card_payment')).to be(true)
    expect { described_class.enabled?(:birthday) }.to raise_error(ArgumentError)
  end

  it 'sends an SMS only while progress SMS and that message are both on' do
    setting = described_class.current
    setting.update!(disabled_sms_messages: ['fee_pending'])

    expect(described_class.sms_message_enabled?('fee_pending')).to be(false)
    expect(described_class.sms_message_enabled?('registered')).to be(true)

    setting.update!(progress_sms_enabled: false)
    expect(described_class.sms_message_enabled?('registered')).to be(false)
  end

  it 'rejects an unknown SMS message' do
    setting = described_class.current
    setting.disabled_sms_messages = ['birthday']

    expect(setting).not_to be_valid
  end

  it 'cannot be destroyed' do
    expect { described_class.current.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
