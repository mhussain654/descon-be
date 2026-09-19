# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetVisaStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns pending with a spoken label when no decision exists' do
    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:status]).to eq('pending')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.visa_outcomes.pending'))
  end

  it 'returns the most recently recorded visa decision with human-readable labels' do
    decision = create(:candidate_visa_decision, candidate_assignment: assignment, outcome_code: 'issued',
                                                decision_date: Date.current)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:outcome_code]).to eq('issued')
    expect(result[:outcome_label]).to eq(I18n.t('api.ai_calls.labels.visa_outcomes.issued'))
    expect(result[:decision_date]).to eq(decision.decision_date.iso8601)
    expect(result[:rejection_reason_label]).to be_nil
  end

  it 'returns a human-readable rejection reason when the visa was rejected' do
    create(:candidate_visa_decision, candidate_assignment: assignment, outcome_code: 'rejected',
                                     rejection_reason_code: 'embassy_rejection', decision_date: Date.current)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:rejection_reason_code]).to eq('embassy_rejection')
    expect(result[:rejection_reason_label])
      .to eq(I18n.t('api.ai_calls.labels.visa_rejection_reasons.embassy_rejection'))
  end
end
