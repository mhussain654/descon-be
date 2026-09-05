# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::DelayedCasesQuery do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:verified_stage) { stage('verified', 5) }
  let(:mobilized_stage) { stage('mobilized', 15) }

  it 'counts a candidate as delayed/critical using their most recent transition into the current stage' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 30.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 10.days)

    result = described_class.call(reference_time: now)

    expect(result).to eq(delayed: 1, critical: 0)
  end

  it 'falls back to the assignment created_at when no stage-history row exists yet' do
    create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 20.days)

    result = described_class.call(reference_time: now)

    expect(result).to eq(delayed: 1, critical: 1)
  end

  it 'excludes candidates below the threshold' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 30.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 2.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 0, critical: 0)
  end

  it 'excludes candidates who already reached the terminal mobilized stage' do
    assignment = create(:candidate_assignment, current_workflow_stage: mobilized_stage, created_at: now - 30.days)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: mobilized_stage,
                                     occurred_at: now - 20.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 0, critical: 0)
  end

  it 'counts critical cases within delayed as well' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 40.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 20.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 1, critical: 1)
  end
end
