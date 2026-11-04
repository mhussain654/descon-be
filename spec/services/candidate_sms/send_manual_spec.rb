# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::SendManual do
  include ActiveJob::TestHelper

  let(:actor) { create(:user, role: 'hr') }
  let(:candidate) { create(:candidate, full_name: 'Daim Javed') }
  let!(:assignment) { create(:candidate_assignment, candidate:) }

  def send_sms(message_code: 'fee_pending', locale: 'en', variables: { 'name' => 'Daim Javed', 'amount' => '1500' })
    described_class.call(candidate:, actor:, message_code:, locale:, variables:)
  end

  def error_field
    yield
  rescue ValidationError => e
    e.field
  end

  describe '.call' do
    context 'with a message that has a template in the chosen language' do
      before { create(:sms_template, message_code: 'fee_pending', template_id_en: '20010', enabled: false) }

      it 'records the SMS as sent by the staff member and queues it, even when it is not sent automatically' do
        delivery = nil
        expect { delivery = send_sms }.to have_enqueued_job(CandidateSms::DeliveryJob)

        expect(delivery).to have_attributes(
          candidate:, candidate_assignment: assignment, sent_by: actor, message_code: 'fee_pending', locale: 'en',
          status: 'pending', variables: { 'name' => 'Daim Javed', 'amount' => '1500' }, manual?: true
        )
      end

      it 'keeps only the values the template uses, trimmed' do
        delivery = send_sms(variables: { 'name' => ' Daim ', 'amount' => '1500', 'extra' => 'x' })

        expect(delivery.variables).to eq('name' => 'Daim', 'amount' => '1500')
      end

      it 'sends again when asked again' do
        2.times { send_sms }

        expect(CandidateSmsDelivery.where(message_code: 'fee_pending').count).to eq(2)
      end

      it 'refuses a missing value, naming it' do
        expect(error_field { send_sms(variables: { 'name' => 'Daim Javed' }) })
          .to eq('sms_message.variables.amount')
        expect(CandidateSmsDelivery.count).to eq(0)
      end

      it 'refuses a language without a template' do
        expect(error_field { send_sms(locale: 'ur') }).to eq('sms_message.locale')
      end

      it 'refuses an unknown language' do
        expect(error_field { send_sms(locale: 'fr') }).to eq('sms_message.locale')
      end
    end

    it 'never sends the login code' do
      create(:sms_template, message_code: 'otp', template_id_en: '11062')

      expect(error_field { send_sms(message_code: 'otp', variables: {}) }).to eq('sms_message.message_code')
    end

    it 'refuses a message with no template row' do
      expect(error_field { send_sms(message_code: 'unknown', variables: {}) }).to eq('sms_message.message_code')
    end

    it 'refuses an inactive candidate' do
      create(:sms_template, message_code: 'fee_pending', template_id_en: '20010')
      candidate.update!(active: false)

      expect(error_field { send_sms }).to eq('sms_message')
    end

    it 'refuses a candidate without an assignment' do
      create(:sms_template, message_code: 'fee_pending', template_id_en: '20010')
      other = create(:candidate)

      expect do
        described_class.call(candidate: other, actor:, message_code: 'fee_pending', locale: 'en',
                             variables: { 'name' => 'x', 'amount' => '1' })
      end.to raise_error(ValidationError)
    end
  end

  describe '.sendable_templates' do
    it 'lists messages with a template id in either language, in candidate order, never the login code' do
      create(:sms_template, message_code: 'otp', template_id_en: '11062')
      create(:sms_template, message_code: 'ticket_handover', template_id_en: nil, template_id_ur: '30002')
      create(:sms_template, message_code: 'documents_submitted', template_id_en: '30001')
      create(:sms_template, message_code: 'fee_pending', template_id_en: nil)

      expect(described_class.sendable_templates.map(&:message_code)).to eq(%w[documents_submitted ticket_handover])
    end
  end
end
