# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilizationProcesses::AssignmentBackfill do
  # Simulates an assignment created before processes existed.
  def unlinked_assignment(country:, stage_code:)
    assignment = create(:candidate_assignment, country:)
    assignment.update_columns(mobilization_process_id: nil, current_mobilization_process_stage_id: nil, # rubocop:disable Rails/SkipsModelValidations
                              current_workflow_stage_id: WorkflowStage.find_by!(code: stage_code).id)
    assignment
  end

  it "links each unlinked assignment to its country's process at its current stage" do
    qatar_assignment = unlinked_assignment(country: process_country(:qatar), stage_code: 'qvc_appointment_booked')
    common_assignment = unlinked_assignment(country: create(:country), stage_code: 'fee_pending')

    result = described_class.call

    expect(result).to have_attributes(linked_count: 2, unmatched_reference_numbers: [])
    expect(qatar_assignment.reload.mobilization_process.code).to eq('qatar_mobilization')
    expect(qatar_assignment.current_mobilization_process_stage.position).to eq(12)
    expect(common_assignment.reload.current_mobilization_process_stage.code).to eq('fee_pending')
  end

  it 'leaves assignments whose stage is not in the resolved process unlinked, and reports them' do
    assignment = unlinked_assignment(country: process_country(:saudi_arabia), stage_code: 'qvc_appointment_booked')

    result = described_class.call

    expect(result).to have_attributes(linked_count: 0, unmatched_reference_numbers: [assignment.reference_number])
    expect(assignment.reload.mobilization_process_id).to be_nil
  end
end
