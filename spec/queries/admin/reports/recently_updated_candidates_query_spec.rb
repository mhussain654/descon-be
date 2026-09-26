# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::RecentlyUpdatedCandidatesQuery do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  let(:registered_stage) { stage('registered', 1) }
  let(:verified_stage) { stage('verified', 5) }

  it "orders by the candidate's most recent transition into their current stage, most recent first" do
    older = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:candidate_stage_history, candidate_assignment: older, to_workflow_stage: verified_stage,
                                     occurred_at: 5.days.ago)

    newer = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:candidate_stage_history, candidate_assignment: newer, to_workflow_stage: verified_stage,
                                     occurred_at: 1.day.ago)

    result = described_class.call

    expect(result.map { |row| row.fetch(:candidate_assignment_public_id) }).to eq(
      [newer.public_id, older.public_id]
    )
  end

  it 'reports the candidate name, reference number and current stage code' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: 1.day.ago)

    row = described_class.call.first

    expect(row).to include(
      candidate_full_name: assignment.candidate.full_name,
      candidate_public_id: assignment.candidate.public_id,
      candidate_assignment_public_id: assignment.public_id,
      reference_number: assignment.reference_number,
      workflow_stage_code: 'verified'
    )
  end

  # Shares LatestStageEntryJoin with DelayedCasesQuery, whose own
  # "stage re-entry robustness" spec already documents why a true multi-row-
  # per-(assignment, to_stage) fan-out can't be reproduced: a unique index
  # (index_stage_histories_on_assignment_and_destination_stage) makes it
  # actually impossible today -- not re-documented/re-tested a second time
  # here for the same shared join.

  it 'respects the limit' do
    3.times do |n|
      assignment = create(:candidate_assignment, current_workflow_stage: verified_stage)
      create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                       occurred_at: n.days.ago)
    end

    expect(described_class.call(limit: 2).size).to eq(2)
  end
end
