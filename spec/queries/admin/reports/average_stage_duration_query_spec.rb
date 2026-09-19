# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::AverageStageDurationQuery do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  let(:registered_stage) { stage('registered', 1) }
  let(:documents_uploaded_stage) { stage('documents_uploaded', 3) }
  let(:verified_stage) { stage('verified', 5) }

  it 'returns nil when no assignment in scope has more than one recorded transition' do
    assignment = create(:candidate_assignment, current_workflow_stage: registered_stage)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: Time.current)

    expect(described_class.call).to be_nil
  end

  it 'averages the gap between consecutive transitions for the same assignment' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: 10.days.ago)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: documents_uploaded_stage,
                                     from_workflow_stage: registered_stage, occurred_at: 6.days.ago)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     from_workflow_stage: documents_uploaded_stage, occurred_at: 2.days.ago)

    # Two gaps: 10d->6d ago = 4 days, 6d->2d ago = 4 days. Average = 4.0.
    expect(described_class.call).to eq(4.0)
  end

  it 'averages across multiple assignments, not just within one' do
    first = create(:candidate_assignment, current_workflow_stage: documents_uploaded_stage)
    create(:candidate_stage_history, candidate_assignment: first, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: 4.days.ago)
    create(:candidate_stage_history, candidate_assignment: first, to_workflow_stage: documents_uploaded_stage,
                                     from_workflow_stage: registered_stage, occurred_at: 2.days.ago)

    second = create(:candidate_assignment, current_workflow_stage: documents_uploaded_stage)
    create(:candidate_stage_history, candidate_assignment: second, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: 8.days.ago)
    create(:candidate_stage_history, candidate_assignment: second, to_workflow_stage: documents_uploaded_stage,
                                     from_workflow_stage: registered_stage, occurred_at: 2.days.ago)

    # Gaps: 2 days (first) and 6 days (second). Average = 4.0.
    expect(described_class.call).to eq(4.0)
  end

  it 'only considers assignments within the given scope' do
    included = create(:candidate_assignment, current_workflow_stage: documents_uploaded_stage)
    create(:candidate_stage_history, candidate_assignment: included, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: 4.days.ago)
    create(:candidate_stage_history, candidate_assignment: included, to_workflow_stage: documents_uploaded_stage,
                                     from_workflow_stage: registered_stage, occurred_at: 2.days.ago)

    excluded_candidate = create(:candidate, active: false)
    excluded = create(:candidate_assignment, candidate: excluded_candidate,
                                             current_workflow_stage: documents_uploaded_stage)
    create(:candidate_stage_history, candidate_assignment: excluded, to_workflow_stage: registered_stage,
                                     from_workflow_stage: nil, occurred_at: 100.days.ago)
    create(:candidate_stage_history, candidate_assignment: excluded, to_workflow_stage: documents_uploaded_stage,
                                     from_workflow_stage: registered_stage, occurred_at: 2.days.ago)

    expect(described_class.call(scope: Candidate.active)).to eq(2.0)
  end
end
