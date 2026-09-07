# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Dashboards::AdminSummaryService do
  it 'assembles candidate workload, workflow-stage queue, document-review queue and payment sections' do
    registered_stage = WorkflowStage.find_or_create_by!(code: 'registered') do |record|
      record.position = 1
      record.system_defined = true
    end
    create(:candidate_assignment, current_workflow_stage: registered_stage, candidate: create(:candidate, active: true))
    create(:candidate_document_submission)
    create(:payment)

    result = described_class.call

    expect(result.fetch(:candidate_workload)).to eq(total_active_candidates: Candidate.active.count)
    expect(result.fetch(:workflow_stage_queue)).to be_an(Array)
    expect(result.fetch(:document_review_queue).keys).to contain_exactly(
      'pending_review', 'verified', 'rejected', 'expired_pcc', 'near_expiry_pcc'
    )
    expect(result.fetch(:payment_summary)).to be_an(Array)
  end
end
