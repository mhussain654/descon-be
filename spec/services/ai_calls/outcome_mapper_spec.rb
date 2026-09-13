# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::OutcomeMapper do
  def extraction(human_answered: true, callback_requested: false, escalation_requested: false, call_resolved: true)
    { human_answered:, callback_requested:, escalation_requested:, call_resolved: }
  end

  it 'maps a resolved, human-answered call' do
    result = described_class.call(telephony_outcome: 'answered', extraction: extraction(call_resolved: true))

    expect(result.outcome).to eq('answered')
    expect(result.outcome_reason).to eq('resolved')
  end

  it 'maps an unresolved, human-answered call' do
    result = described_class.call(telephony_outcome: 'answered', extraction: extraction(call_resolved: false))

    expect(result.outcome).to eq('answered')
    expect(result.outcome_reason).to eq('unresolved')
  end

  it 'maps a candidate-requested callback ahead of an escalation or resolution flag' do
    result = described_class.call(
      telephony_outcome: 'answered',
      extraction: extraction(callback_requested: true, escalation_requested: true, call_resolved: true)
    )

    expect(result.outcome).to eq('callback_required')
    expect(result.outcome_reason).to eq('candidate_requested')
  end

  it 'maps an agent escalation' do
    result = described_class.call(
      telephony_outcome: 'answered',
      extraction: extraction(escalation_requested: true, call_resolved: true)
    )

    expect(result.outcome).to eq('callback_required')
    expect(result.outcome_reason).to eq('agent_escalation')
  end

  %w[busy no_answer voicemail provider_failure].each do |reason|
    it "maps telephony_outcome #{reason} to not_answered" do
      result = described_class.call(telephony_outcome: reason)

      expect(result.outcome).to eq('not_answered')
      expect(result.outcome_reason).to eq(reason)
    end
  end

  it 'routes a missing extraction to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'answered', extraction: nil)

    expect(result.outcome).to be_nil
    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'routes a non-hash extraction to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'answered', extraction: 'not-a-hash')

    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'routes extraction missing human_answered to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'answered', extraction: extraction.except(:human_answered))

    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'routes a self-contradictory extraction (telephony answered, human never answered) to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'answered', extraction: extraction(human_answered: false))

    expect(result.outcome).to be_nil
    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'routes extraction missing call_resolved (and no callback/escalation) to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'answered', extraction: extraction.except(:call_resolved))

    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'routes an unrecognized telephony_outcome to needs_manual_review' do
    result = described_class.call(telephony_outcome: 'unknown')

    expect(result.outcome).to be_nil
    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'accepts string-keyed extraction hashes' do
    result = described_class.call(
      telephony_outcome: 'answered',
      extraction: { 'human_answered' => true, 'call_resolved' => true, 'callback_requested' => false,
                    'escalation_requested' => false }
    )

    expect(result.outcome).to eq('answered')
    expect(result.outcome_reason).to eq('resolved')
  end
end
