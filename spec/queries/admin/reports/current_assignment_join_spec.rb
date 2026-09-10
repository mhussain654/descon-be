# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::CurrentAssignmentJoin do
  it 'joins each candidate to their most recently created assignment' do
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, created_at: 2.days.ago)
    newer = create(:candidate_assignment, candidate:, created_at: 1.hour.ago)

    joined_assignment_id = described_class.call.where(id: candidate.id).pick(Arel.sql('current_assignments.id'))

    expect(joined_assignment_id).to eq(newer.id)
  end

  it 'excludes candidates with no assignment' do
    create(:candidate)
    assigned = create(:candidate_assignment).candidate

    expect(described_class.call.pluck(:id)).to eq([assigned.id])
  end

  it 'accepts a pre-scoped relation' do
    active = create(:candidate_assignment, candidate: create(:candidate, active: true)).candidate
    create(:candidate_assignment, candidate: create(:candidate, active: false))

    result = described_class.call(scope: Candidate.where(active: true))

    expect(result.pluck(:id)).to eq([active.id])
  end
end
