# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetPaymentStatus do
  it 'returns the payment eligibility summary' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result).to eq(Payments::EligibilitySerializer.new(Payments::EligibilityService.call(candidate:)).as_json)
  end
end
