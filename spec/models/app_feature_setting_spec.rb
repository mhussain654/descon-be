# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppFeatureSetting do
  it 'starts with every switch on' do
    setting = described_class.current

    expect(described_class::SWITCHES.map { |switch| setting.public_send(:"#{switch}_enabled") }).to all(be(true))
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

  it 'cannot be destroyed' do
    expect { described_class.current.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
