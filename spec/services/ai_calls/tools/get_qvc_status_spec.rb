# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetQvcStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_scheduled with a spoken label when no attempt exists' do
    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:status]).to eq('not_scheduled')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.qvc_statuses.not_scheduled'))
  end

  it 'returns the latest QVC attempt with a spoken label for its status' do
    create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 1, outcome_code: 're_medical',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: assignment.created_by)
    latest = create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 2)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(latest.public_id)
    expect(result[:attempt_number]).to eq(2)
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.qvc_statuses.scheduled'))
  end
end
