# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetApplicationStatus do
  it 'returns the candidate status, workflow progress, and human-readable stage names' do
    candidate = create(:candidate, status_code: 'registered')
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:candidate_status]).to eq('registered')
    expect(result[:current_stage_code]).to eq(assignment.current_workflow_stage.code)
    expect(result[:current_stage_name]).to eq(assignment.current_workflow_stage.name_for)
    expect(result[:next_stage_name]).to eq(WorkflowStage.find_by(code: 'documents_pending').name_for)
    expect(result).to have_key(:progress_percentage)
  end

  it 'returns no next_stage_name once the assignment has reached the terminal stage' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    assignment.update!(current_workflow_stage: WorkflowStage.find_by(code: 'mobilized'))
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:next_stage_name]).to be_nil
  end
end
