# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::TransitionResultSerializer do
  before do
    ensure_canonical_workflow_stages!
  end

  it 'serializes the candidate-safe workflow transition result' do
    candidate = create(:candidate, status_code: 'documents_pending')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending'),
      created_at: Time.zone.parse('2026-08-29T09:00:00Z'),
      updated_at: Time.zone.parse('2026-08-29T09:00:00Z')
    )
    history_entry = create(
      :candidate_stage_history,
      candidate_assignment: assignment,
      from_workflow_stage: WorkflowStage.find_by!(code: 'registered'),
      to_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending'),
      occurred_at: Time.zone.parse('2026-08-29T09:00:00Z'),
      reason_code: 'manual_update',
      metadata: { 'source' => 'manual' }
    )
    snapshot = CandidateWorkflows::StateSnapshotService.call(candidate:)

    serialized = described_class.new({ snapshot:, history_entry: }).as_json

    expect(serialized).to include(
      workflow: include(
        candidate_id: candidate.public_id,
        assignment_id: assignment.public_id,
        candidate_status: 'documents_pending',
        current_stage: include(
          code: 'documents_pending',
          status: 'current',
          started_at: '2026-08-29T09:00:00Z'
        ),
        completed_count: 1,
        total_count: 15,
        progress_percentage: 6
      ),
      transition: include(
        from_stage: include(code: 'registered', position: 1),
        to_stage: include(code: 'documents_pending', position: 2),
        occurred_at: '2026-08-29T09:00:00Z',
        reason_code: 'manual_update',
        details: { 'source' => 'manual' }
      )
    )
    expect(serialized.fetch(:transition)).not_to have_key(:actor)
  end
end
