# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflowEvent, type: :model do
  subject(:candidate_workflow_event) { build(:candidate_workflow_event) }

  it { is_expected.to belong_to(:candidate) }
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:candidate_stage_history) }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'validates the event code format' do
    candidate_workflow_event.event_code = 'not-valid'

    expect(candidate_workflow_event).not_to be_valid
    expect(candidate_workflow_event.errors[:event_code]).to be_present
  end

  it 'requires payload to be present even when empty metadata is intended' do
    candidate_workflow_event.payload = nil

    expect(candidate_workflow_event).not_to be_valid
    expect(candidate_workflow_event.errors[:payload]).to be_present
  end

  it 'keeps candidate and assignment references consistent' do
    candidate_workflow_event.candidate = create(:candidate)

    expect(candidate_workflow_event).not_to be_valid
    expect(candidate_workflow_event.errors[:candidate_assignment]).to include('is invalid')
  end

  it 'keeps assignment and history references consistent' do
    other_assignment = create(:candidate_assignment)
    other_history = create(:candidate_stage_history, candidate_assignment: other_assignment)
    candidate_workflow_event.candidate_stage_history = other_history

    expect(candidate_workflow_event).not_to be_valid
    expect(candidate_workflow_event.errors[:candidate_stage_history]).to include('is invalid')
  end

  it 'is immutable after creation' do
    persisted_event = create(:candidate_workflow_event)

    expect { persisted_event.update!(published_at: Time.current) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { persisted_event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
