# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Configuration do
  subject(:configuration) { described_class.new }

  def with_settings(values)
    allow(Rails.application).to receive(:config_for).with(:sendpk).and_return(values)
  end

  describe '#sendpk_template_id' do
    it 'returns the Urdu template for an Urdu locale when one is set' do
      with_settings(template_id: '10790', template_id_ur: '10791')

      expect(configuration.sendpk_template_id('ur')).to eq('10791')
    end

    it 'returns the default template for any other locale' do
      with_settings(template_id: '10790', template_id_ur: '10791')

      expect(configuration.sendpk_template_id('en')).to eq('10790')
      expect(configuration.sendpk_template_id).to eq('10790')
    end

    it 'falls back to the default template when no Urdu template is configured' do
      with_settings(template_id: '10790', template_id_ur: '')

      expect(configuration.sendpk_template_id('ur')).to eq('10790')
    end
  end

  describe 'defaults and blanks' do
    it 'treats blank settings as unset and applies the base URL default' do
      with_settings(api_key: '', sender_id: ' ', base_url: '', open_timeout: 5, read_timeout: 10)

      expect(configuration.sendpk_api_key).to be_nil
      expect(configuration.sendpk_sender_id).to be_nil
      expect(configuration.sendpk_base_url).to eq('https://sendpk.com')
      expect([configuration.sendpk_open_timeout, configuration.sendpk_read_timeout]).to eq([5, 10])
    end
  end

  describe 'config/sendpk.yml' do
    it 'renders for the test environment with a fake api key and the default timeouts' do
      loaded = Rails.application.config_for(:sendpk)

      expect(loaded).to include(api_key: 'test-sendpk-api-key', open_timeout: 5, read_timeout: 10)
    end
  end
end
