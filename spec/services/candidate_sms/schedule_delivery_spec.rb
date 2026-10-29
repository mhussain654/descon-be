# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::ScheduleDelivery do
  let(:candidate) { create(:candidate, full_name: 'Daim Javed') }
  let(:assignment) { create(:candidate_assignment, candidate:) }

  def schedule(dedupe_key: 'medical_appointment:1', variables: { date: '04-11-2026' })
    described_class.call(assignment:, message_code: 'medical_appointment', dedupe_key:, variables:)
  end

  it 'records a pending SMS with the candidate name and values as text, and queues it' do
    expect { schedule }.to have_enqueued_job(CandidateSms::DeliveryJob)

    delivery = CandidateSmsDelivery.sole
    expect(delivery).to have_attributes(
      candidate:, candidate_assignment: assignment, message_code: 'medical_appointment', status: 'pending',
      locale: 'en', variables: { 'name' => 'Daim Javed', 'date' => '04-11-2026' }
    )
    expect(CandidateSms::DeliveryJob).to have_been_enqueued.with(candidate_sms_delivery_id: delivery.id)
  end

  it 'sends the same event once, without breaking the surrounding transaction' do
    ActiveRecord::Base.transaction do
      schedule
      expect { schedule }.not_to have_enqueued_job(CandidateSms::DeliveryJob)
      expect(Candidate.count).to be_positive
    end

    expect(CandidateSmsDelivery.count).to eq(1)
  end

  it 'uses the candidate’s Urdu preference' do
    candidate.update!(preferred_locale: 'ur')

    schedule

    expect(CandidateSmsDelivery.sole.locale).to eq('ur')
  end

  it 'records a message switched off in App Settings as skipped and never queues it' do
    AppFeatureSetting.current.update!(disabled_sms_messages: ['medical_appointment'])

    expect { schedule }.not_to have_enqueued_job(CandidateSms::DeliveryJob)
    expect(CandidateSmsDelivery.sole).to have_attributes(status: 'skipped', error_code: 'disabled')
  end

  it 'skips every message while progress SMS are switched off, and does not send them when turned back on' do
    AppFeatureSetting.current.update!(progress_sms_enabled: false)
    schedule
    AppFeatureSetting.current.update!(progress_sms_enabled: true)

    expect { schedule }.not_to have_enqueued_job(CandidateSms::DeliveryJob)
    expect(CandidateSmsDelivery.sole.status).to eq('skipped')
  end

  it 'sends nothing to an inactive candidate' do
    candidate.update!(active: false)

    expect { schedule }.not_to have_enqueued_job(CandidateSms::DeliveryJob)
    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'refuses a message it does not know' do
    expect do
      described_class.call(assignment:, message_code: 'birthday', dedupe_key: 'birthday:1')
    end.to raise_error(ArgumentError, /birthday/)
  end

  describe '.format_date' do
    it 'writes dates as day-month-year' do
      expect(described_class.format_date(Date.new(2026, 11, 4))).to eq('04-11-2026')
      expect(described_class.format_date(nil)).to be_nil
    end
  end
end
