# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetPaymentStatus do
  it 'returns the payment eligibility summary plus human-readable stage names and blocking-reason descriptions' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)
    eligibility = Payments::EligibilityService.call(candidate:)

    expect(result).to include(Payments::EligibilitySerializer.new(eligibility).as_json)
    expect(result[:current_stage_name]).to eq(WorkflowStage.find_by(code: eligibility.current_stage_code)&.name_for)
    expect(result[:blocking_reason_descriptions]).to eq(
      eligibility.blocking_reasons.map { |reason| I18n.t("api.ai_calls.labels.payment_blocking_reasons.#{reason}") }
    )
  end

  it 'falls back to a humanized label for an unmapped blocking reason' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)
    stubbed_result = Payments::EligibilityService.call(candidate:).dup
    stubbed_result.blocking_reasons = ['some_new_reason']
    allow(Payments::EligibilityService).to receive(:call).and_return(stubbed_result)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:blocking_reason_descriptions]).to eq(['Some new reason'])
  end
end
