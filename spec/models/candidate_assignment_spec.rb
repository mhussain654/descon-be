# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAssignment, type: :model do
  subject(:candidate_assignment) { build(:candidate_assignment) }

  it { is_expected.to belong_to(:candidate) }
  it { is_expected.to belong_to(:country) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:craft) }
  it { is_expected.to belong_to(:current_workflow_stage).class_name('WorkflowStage') }

  it 'normalizes the QVC outcome code' do
    candidate_assignment.qvc_outcome_code = ' RE_MEDICAL_REQUIRED '
    candidate_assignment.qvc_outcome_date = Date.current
    candidate_assignment.validate

    expect(candidate_assignment.qvc_outcome_code).to eq('re_medical')
  end

  describe 'registration number' do
    it 'is optional, a whole number above zero' do
      expect(candidate_assignment.tap { |a| a.registration_number = nil }).to be_valid
      candidate_assignment.registration_number = 0
      expect(candidate_assignment).not_to be_valid
      expect(candidate_assignment.errors[:registration_number]).to be_present
    end

    it 'is unique across the organisation, whatever the campaign' do
      create(:candidate_assignment, campaign: create(:campaign), registration_number: 500_001)

      expect(build(:candidate_assignment, campaign: create(:campaign), registration_number: 500_001)).not_to be_valid
      expect(described_class.registration_number_taken?(500_001)).to be(true)
      expect(described_class.registration_number_taken?(nil)).to be(false)
    end

    it 'names the assignment in payment order ids, or the candidate id before it is set' do
      assignment = create(:candidate_assignment, registration_number: nil)
      expect(assignment.order_reference).to eq("C#{assignment.candidate_id}")

      assignment.update!(registration_number: 42)
      expect(assignment.order_reference).to eq(42)
    end

    it 'is unique at the database level' do
      create(:candidate_assignment, registration_number: 7)
      duplicate = build(:candidate_assignment, registration_number: 7)
      duplicate.validate # fills the callback-set columns; the save below skips the model's own check

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it 'requires the QVC outcome code and date together' do
    candidate_assignment.qvc_outcome_code = 'approved'
    candidate_assignment.qvc_outcome_date = nil
    candidate_assignment.valid?

    expect(candidate_assignment.errors[:qvc_outcome_date]).to include("can't be blank")
  end
end
