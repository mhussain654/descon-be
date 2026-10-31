# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsTemplate do
  it 'covers the OTP and every progress SMS' do
    expect(described_class::MESSAGE_CODES).to eq(['otp'] + CandidateSmsDelivery::MESSAGE_CODES)
  end

  it 'strips the template ids and stores a blank one as unset' do
    template = create(:sms_template, template_id_en: ' 20001 ', template_id_ur: ' ')

    expect(template).to have_attributes(template_id_en: '20001', template_id_ur: nil)
  end

  it 'rejects a template id that is not a send.pk number' do
    expect(build(:sms_template, template_id_en: 'abc')).not_to be_valid
    expect(build(:sms_template, template_id_ur: '12 34')).not_to be_valid
  end

  it 'rejects an unknown message and a second row for the same message' do
    create(:sms_template, message_code: 'fee_pending')

    expect(build(:sms_template, message_code: 'birthday')).not_to be_valid
    expect(described_class.new(message_code: 'fee_pending')).not_to be_valid
  end

  it 'never lets the OTP be switched off, in the model or the database' do
    otp = create(:sms_template, message_code: 'otp')

    expect(otp.always_enabled?).to be(true)
    expect(otp.update(enabled: false)).to be(false)
    expect { otp.update_column(:enabled, false) }.to raise_error(ActiveRecord::StatementInvalid) # rubocop:disable Rails/SkipsModelValidations
  end

  describe '.enabled?' do
    it 'is false only for a message switched off, and true for one with no row yet' do
      create(:sms_template, message_code: 'fee_pending', enabled: false)
      create(:sms_template, message_code: 'registered')
      described_class.where(message_code: 'visa_issued').delete_all

      expect(described_class.enabled?(:fee_pending)).to be(false)
      expect(described_class.enabled?('registered')).to be(true)
      expect(described_class.enabled?('visa_issued')).to be(true)
    end
  end

  describe '#variables' do
    it 'lists the values each message sends, the candidate name by default' do
      expect(build(:sms_template, message_code: 'otp').variables).to eq(%w[code minutes])
      expect(build(:sms_template, message_code: 'fee_pending').variables).to eq(%w[name amount])
      expect(build(:sms_template, message_code: 'visa_issued').variables).to eq(%w[name])
    end
  end
end
