# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateStageHistory, type: :model do
  subject(:candidate_stage_history) { build(:candidate_stage_history) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:from_workflow_stage).class_name('WorkflowStage').optional }
  it { is_expected.to belong_to(:to_workflow_stage).class_name('WorkflowStage') }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'allows the first stage event to omit the previous stage' do
    candidate_stage_history.from_workflow_stage = nil

    expect(candidate_stage_history).to be_valid
  end

  it 'rejects transitions that do not change stage' do
    stage = create(:workflow_stage, :registered)
    candidate_stage_history.from_workflow_stage = stage
    candidate_stage_history.to_workflow_stage = stage

    expect(candidate_stage_history).not_to be_valid
    expect(candidate_stage_history.errors[:from_workflow_stage]).to be_present
  end

  it 'is immutable after creation' do
    stage_history = create(:candidate_stage_history)

    expect { stage_history.update!(note: 'Changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { stage_history.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'enforces distinct transitions at the database level' do
    assignment = create(:candidate_assignment)
    stage = create(:workflow_stage, :registered)

    expect do
      described_class.connection.exec_insert(
        <<~SQL.squish,
          INSERT INTO candidate_stage_histories (
            candidate_assignment_id,
            from_workflow_stage_id,
            to_workflow_stage_id,
            occurred_at,
            created_at,
            updated_at
          )
          VALUES (
            #{assignment.id},
            #{stage.id},
            #{stage.id},
            #{described_class.connection.quote(Time.current)},
            #{described_class.connection.quote(Time.current)},
            #{described_class.connection.quote(Time.current)}
          )
        SQL
        'SQL'
      )
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'requires metadata to be present even when no extra evidence is stored' do
    candidate_stage_history.metadata = nil

    expect(candidate_stage_history).not_to be_valid
    expect(candidate_stage_history.errors[:metadata]).to be_present
  end
end
