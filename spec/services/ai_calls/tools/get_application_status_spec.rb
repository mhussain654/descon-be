# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetApplicationStatus do
  it 'returns the candidate status and workflow progress' do
    candidate = create(:candidate, status_code: 'registered')
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:candidate_status]).to eq('registered')
    expect(result[:current_stage]).to eq(assignment.current_workflow_stage.code)
    expect(result).to have_key(:progress_percentage)
  end
end
