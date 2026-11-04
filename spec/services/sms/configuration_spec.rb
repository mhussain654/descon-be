# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Configuration do
  subject(:configuration) { described_class.new }

  def with_settings(values)
    allow(Rails.application).to receive(:config_for).with(:sendpk).and_return(values)
  end

  describe '#sendpk_template_id' do
    before do
      create(:sms_template, message_code: 'otp', template_id_en: '11062', template_id_ur: '11065')
      create(:sms_template, message_code: 'registered', template_id_en: '20001', template_id_ur: nil)
    end

    it 'returns the Urdu template for an Urdu locale when one is set' do
      expect(configuration.sendpk_template_id(:otp, 'ur')).to eq('11065')
    end

    it 'returns the English template for any other locale' do
      expect(configuration.sendpk_template_id(:otp, 'en')).to eq('11062')
      expect(configuration.sendpk_template_id('otp')).to eq('11062')
    end

    it 'falls back to the English template when no Urdu template is set' do
      expect(configuration.sendpk_template_id(:registered, 'ur')).to eq('20001')
    end

    it 'is unset for a message with no row yet' do
      SmsTemplate.where(message_code: 'fee_pending').delete_all

      expect(configuration.sendpk_template_id(:fee_pending, 'en')).to be_nil
    end

    it 'reads each message from the database once' do
      allow(SmsTemplate).to receive(:find_for).and_call_original

      configuration.sendpk_template_id(:otp, 'ur')
      configuration.sendpk_template_id(:otp, 'en')

      expect(SmsTemplate).to have_received(:find_for).with('otp').once
    end
  end

  describe '#sendpk_urdu_template_id' do
    it 'is the Urdu template only for an Urdu locale' do
      create(:sms_template, message_code: 'otp', template_id_en: '11062', template_id_ur: '11065')

      expect(configuration.sendpk_urdu_template_id(:otp, 'ur')).to eq('11065')
      expect(configuration.sendpk_urdu_template_id(:otp, 'en')).to be_nil
    end
  end

  describe 'defaults and blanks' do
    it 'treats blank settings as unset and applies the base URL default' do
      with_settings(api_key: '', otp_sender_id: ' ', sms_sender_id: '', base_url: '', open_timeout: 5, read_timeout: 10)

      expect(configuration.sendpk_api_key).to be_nil
      expect(configuration.sendpk_sender_id(:otp)).to be_nil
      expect(configuration.sendpk_sender_id(:visa_issued)).to be_nil
      expect(configuration.sendpk_base_url).to eq('https://sendpk.com')
      expect([configuration.sendpk_open_timeout, configuration.sendpk_read_timeout]).to eq([5, 10])
    end
  end

  describe '#sendpk_sender_id' do
    it 'sends the login code from the short code and every other SMS from the brand name' do
      expect(configuration.sendpk_sender_id(:otp)).to eq('8062050')
      expect(configuration.sendpk_sender_id('visa_issued')).to eq('Descon')
      expect(configuration.sendpk_sender_id).to eq('Descon')
    end
  end

  describe 'config/sendpk.yml' do
    it 'renders for the test environment with a fake api key and the default timeouts' do
      loaded = Rails.application.config_for(:sendpk)

      expect(loaded).to include(api_key: 'test-sendpk-api-key', open_timeout: 5, read_timeout: 10)
    end
  end
end
