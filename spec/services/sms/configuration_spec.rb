# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Configuration do
  subject(:configuration) { described_class.new }

  def with_env(values)
    allow(ENV).to receive(:[]).and_call_original
    values.each { |key, value| allow(ENV).to receive(:[]).with(key).and_return(value) }
  end

  describe '#sendpk_template_id' do
    it 'returns the Urdu template for an Urdu locale when one is set' do
      with_env('OTP_TEMPLATE_ID' => '10790', 'OTP_TEMPLATE_ID_UR' => '10791')

      expect(configuration.sendpk_template_id('ur')).to eq('10791')
    end

    it 'returns the default template for any other locale' do
      with_env('OTP_TEMPLATE_ID' => '10790', 'OTP_TEMPLATE_ID_UR' => '10791')

      expect(configuration.sendpk_template_id('en')).to eq('10790')
      expect(configuration.sendpk_template_id).to eq('10790')
    end

    it 'falls back to the default template when no Urdu template is configured' do
      with_env('OTP_TEMPLATE_ID' => '10790', 'OTP_TEMPLATE_ID_UR' => nil)

      expect(configuration.sendpk_template_id('ur')).to eq('10790')
    end
  end
end
