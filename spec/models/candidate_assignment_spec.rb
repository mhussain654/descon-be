# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAssignment, type: :model do
  subject(:candidate_assignment) { build(:candidate_assignment) }

  it { is_expected.to belong_to(:candidate) }
  it { is_expected.to belong_to(:country) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:craft) }
  it { is_expected.to belong_to(:current_workflow_stage).class_name('WorkflowStage') }

  it 'normalizes the reference number and QVC outcome code' do
    candidate_assignment.reference_number = ' des-0001 '
    candidate_assignment.qvc_outcome_code = ' PASSED '
    candidate_assignment.qvc_outcome_date = Date.current
    candidate_assignment.validate

    expect(candidate_assignment.reference_number).to eq('DES-0001')
    expect(candidate_assignment.qvc_outcome_code).to eq('passed')
  end

  it 'validates reference number uniqueness' do
    existing_assignment = create(:candidate_assignment, reference_number: 'DES-2026-001')
    duplicate_assignment = build(:candidate_assignment, reference_number: existing_assignment.reference_number)

    expect(duplicate_assignment).not_to be_valid
    expect(duplicate_assignment.errors[:reference_number]).to include('has already been taken')
  end

  it 'requires the QVC outcome code and date together' do
    candidate_assignment.qvc_outcome_code = 'passed'
    candidate_assignment.qvc_outcome_date = nil
    candidate_assignment.valid?

    expect(candidate_assignment.errors[:qvc_outcome_date]).to include("can't be blank")
  end

  it 'enforces reference uniqueness at the database level' do
    create(:candidate_assignment, reference_number: 'DES-2026-001')

    expect do
      described_class.connection.exec_insert(
        <<~SQL.squish,
          INSERT INTO candidate_assignments (
            public_id,
            candidate_id,
            country_id,
            project_id,
            craft_id,
            reference_number,
            current_workflow_stage_id,
            created_by_id,
            created_at,
            updated_at
          )
          VALUES (
            #{described_class.connection.quote(SecureRandom.uuid)},
            #{create(:candidate).id},
            #{create(:country).id},
            #{create(:project).id},
            #{create(:craft).id},
            'DES-2026-001',
            #{create(:workflow_stage).id},
            #{create(:user).id},
            #{described_class.connection.quote(Time.current)},
            #{described_class.connection.quote(Time.current)}
          )
        SQL
        'SQL'
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
