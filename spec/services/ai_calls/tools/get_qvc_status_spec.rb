# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetQvcStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_scheduled when no attempt exists' do
    expect(described_class.call(candidate_ai_call: call_record)).to eq(status: 'not_scheduled')
  end

  it 'returns the latest QVC attempt' do
    create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 1, outcome_code: 're_medical',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: assignment.created_by)
    latest = create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 2)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(latest.public_id)
    expect(result[:attempt_number]).to eq(2)
  end
end
