# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateStageHistory, type: :model do
  subject(:candidate_stage_history) do
    build(:candidate_stage_history, candidate_assignment: create(:candidate_assignment))
  end

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:from_workflow_stage).class_name('WorkflowStage').optional }
  it { is_expected.to belong_to(:to_workflow_stage).class_name('WorkflowStage') }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'allows the first stage event to omit the previous stage' do
    candidate_stage_history.from_workflow_stage = nil

    expect(candidate_stage_history).to be_valid
    expect(candidate_stage_history.snapshot_stage(:from)).to be_nil
  end

  it "links the assignment's process and snapshots both ends of the transition" do
    candidate_stage_history.validate

    expect(candidate_stage_history).to have_attributes(
      mobilization_process: candidate_stage_history.candidate_assignment.mobilization_process,
      stage_code: 'documents_pending', position: 2, from_stage_code: 'registered', from_position: 1,
      stage_name_en: 'Documents Pending'
    )
    I18n.with_locale(:ur) do
      expect(candidate_stage_history.snapshot_stage(:to)).to eq(
        code: 'documents_pending', name: candidate_stage_history.stage_name_ur, position: 2
      )
    end
  end

  it 'serves history from the snapshot, not the current catalog label' do
    candidate_stage_history.save!
    candidate_stage_history.update_columns(stage_name_en: 'Docs Pending (at the time)') # rubocop:disable Rails/SkipsModelValidations

    expect(CandidateWorkflows::HistoryStageReference.to(candidate_stage_history.reload))
      .to include(name: 'Docs Pending (at the time)')
  end

  it 'requires the process links and destination snapshot' do
    history = build(:candidate_stage_history, candidate_assignment: create(:candidate_assignment),
                                              to_workflow_stage: create(:workflow_stage))

    expect(history).not_to be_valid
    expect(history.errors.attribute_names).to include(:to_mobilization_process_stage, :position)
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
