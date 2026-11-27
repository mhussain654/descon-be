# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpayReferenceNumber do
  describe '.without_institution' do
    it 'removes the institution code KuickPay puts in front of its reference number' do
      expect(described_class.without_institution('10420261105039065', '10420')).to eq('261105039065')
    end

    it 'keeps a value that does not start with the code, or is only the code' do
      expect(described_class.without_institution('261105039065', '10420')).to eq('261105039065')
      expect(described_class.without_institution('10420', '10420')).to eq('10420')
      expect(described_class.without_institution('10420261105039065', nil)).to eq('10420261105039065')
    end
  end
end
