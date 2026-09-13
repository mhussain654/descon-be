# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::LinkVerifiedCandidateService do
  it 'links the candidate and assignment onto the call and its communication' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound)

    described_class.call(candidate_ai_call: call_record, candidate:, assignment:)

    expect(call_record.reload.candidate).to eq(candidate)
    expect(call_record.candidate_assignment).to eq(assignment)
    expect(call_record.communication.reload.candidate_assignment).to eq(assignment)
  end

  it 'is a no-op when the call is already linked' do
    candidate = create(:candidate)
    other_candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, candidate:, candidate_assignment: assignment)

    described_class.call(candidate_ai_call: call_record, candidate: other_candidate, assignment: nil)

    expect(call_record.reload.candidate).to eq(candidate)
  end
end
