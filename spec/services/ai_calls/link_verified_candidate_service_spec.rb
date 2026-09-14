# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::LinkVerifiedCandidateService do
  it 'links the candidate and assignment onto the call and its communication' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound)

    result = described_class.call(candidate_ai_call: call_record, candidate:, assignment:)

    expect(result.linked).to be(true)
    expect(result.mismatch).to be_nil
    expect(call_record.reload.candidate).to eq(candidate)
    expect(call_record.candidate_assignment).to eq(assignment)
    expect(call_record.communication.reload.candidate_assignment).to eq(assignment)
  end

  it 'is a no-op that reports linked when re-linking to the same candidate and assignment it already has' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, candidate:, candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record, candidate:, assignment:)

    expect(result.linked).to be(true)
    expect(result.mismatch).to be_nil
  end

  # Regression for a caller-ID pre-link (candidate A) later proving
  # knowledge of a different candidate's (B) reference number + CNIC --
  # the call must never end up "verified" while still pointed at A. See
  # AiCalls::Tools::VerifyCallerIdentity, which must treat this mismatch as
  # a failed verification, not silently keep A linked and report success.
  it 'reports a mismatch, without changing the link, when already linked to a different candidate' do
    candidate_a = create(:candidate)
    assignment_a = create(:candidate_assignment, candidate: candidate_a)
    candidate_b = create(:candidate)
    assignment_b = create(:candidate_assignment, candidate: candidate_b)
    call_record = create(:candidate_ai_call, candidate: candidate_a, candidate_assignment: assignment_a)

    result = described_class.call(candidate_ai_call: call_record, candidate: candidate_b, assignment: assignment_b)

    expect(result.linked).to be(false)
    expect(result.mismatch).to be(true)
    expect(call_record.reload.candidate).to eq(candidate_a)
    expect(call_record.candidate_assignment).to eq(assignment_a)
  end

  it 'reports a mismatch when already linked to the same candidate but a different assignment' do
    candidate = create(:candidate)
    original_assignment = create(:candidate_assignment, candidate:)
    other_assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, candidate:, candidate_assignment: original_assignment)

    result = described_class.call(candidate_ai_call: call_record, candidate:, assignment: other_assignment)

    expect(result.linked).to be(false)
    expect(result.mismatch).to be(true)
    expect(call_record.reload.candidate_assignment).to eq(original_assignment)
  end
end
