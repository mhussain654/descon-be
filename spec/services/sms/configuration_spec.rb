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
    it 'sends the login code from the OTP sender and every other SMS from the SMS sender' do
      with_settings(api_key: 'key', otp_sender_id: '8062050', sms_sender_id: 'Descon', base_url: 'https://sendpk.com',
                    open_timeout: 5, read_timeout: 10)

      expect(configuration.sendpk_sender_id(:otp)).to eq('8062050')
      expect(configuration.sendpk_sender_id('visa_issued')).to eq('Descon')
      expect(configuration.sendpk_sender_id).to eq('Descon')
    end

    # send.pk approved the "DESCON MPS" mask, so every SMS goes out from it.
    it 'sends every SMS from the approved DESCON MPS mask' do
      expect([configuration.sendpk_sender_id(:otp), configuration.sendpk_sender_id('fee_pending')])
        .to eq(['DESCON MPS', 'DESCON MPS'])
    end

    context 'with a Zong number, while Zong has not approved the mask' do
      it 'sends every SMS from the short code, whatever the number format' do
        senders = ['923174851211', '+923101234567', '03191234567'].flat_map do |to|
          [configuration.sendpk_sender_id(:otp, to:), configuration.sendpk_sender_id('fee_pending', to:)]
        end

        expect(senders.uniq).to eq(['8062050'])
      end

      it 'keeps the mask for other networks' do
        senders = %w[923001234567 923451234567 923211234567 03331234567].map do |to|
          configuration.sendpk_sender_id(:otp, to:)
        end

        expect(senders.uniq).to eq(['DESCON MPS'])
      end
    end

    it 'sends to Zong from the mask once the Zong sender is cleared' do
      with_settings(api_key: 'key', otp_sender_id: 'DESCON MPS', sms_sender_id: 'DESCON MPS', zong_sender_id: '',
                    base_url: 'https://sendpk.com', open_timeout: 5, read_timeout: 10)

      expect(configuration.sendpk_sender_id(:otp, to: '923174851211')).to eq('DESCON MPS')
    end
  end

  describe 'config/sendpk.yml' do
    it 'renders for the test environment with a fake api key and the default timeouts' do
      loaded = Rails.application.config_for(:sendpk)

      expect(loaded).to include(api_key: 'test-sendpk-api-key', open_timeout: 5, read_timeout: 10)
    end
  end
end
