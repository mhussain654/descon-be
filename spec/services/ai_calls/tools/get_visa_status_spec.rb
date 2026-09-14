# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetVisaStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns pending when no decision exists' do
    expect(described_class.call(candidate_ai_call: call_record)).to eq(status: 'pending')
  end

  it 'returns the most recently recorded visa decision' do
    decision = create(:candidate_visa_decision, candidate_assignment: assignment, outcome_code: 'issued',
                                                decision_date: Date.current)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:outcome_code]).to eq('issued')
    expect(result[:decision_date]).to eq(decision.decision_date.iso8601)
  end
end
