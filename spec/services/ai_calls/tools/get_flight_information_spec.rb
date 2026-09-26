# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetFlightInformation do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_yet_available with a spoken label when no flight detail exists' do
    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:status]).to eq('not_yet_available')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.flight_statuses.not_yet_available'))
  end

  it 'labels a booked-but-not-yet-departed flight as scheduled' do
    detail = create(:candidate_flight_detail, candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(detail.public_id)
    expect(result[:airline]).to eq('Qatar Airways')
    expect(result[:status]).to eq('flight_scheduled')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.flight_statuses.flight_scheduled'))
  end

  it 'labels a departed flight as mobilized' do
    detail = create(:candidate_flight_detail, :mobilized, candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(detail.public_id)
    expect(result[:status]).to eq('mobilized')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.flight_statuses.mobilized'))
  end
end
