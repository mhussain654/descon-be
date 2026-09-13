# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::TransitionSideEffectRecorder do
  let(:assignment) { create(:candidate_assignment) }
  let(:candidate) { assignment.candidate }
  let(:destination_stage) { WorkflowStage.find_by!(code: 'verified') }
  let(:history_entry) do
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: destination_stage)
  end

  def call_recorder
    described_class.call(
      history_entry:,
      context: { candidate:, assignment:, destination_stage:, current_stage: nil },
      transition: { request_id: 'req-1', transitioned_at: Time.current, evidence: {} }
    )
  end

  it 'enqueues AiCalls::TriggerWorkflowStageCallJob with the assignment and destination stage' do
    expect { call_recorder }.to have_enqueued_job(AiCalls::TriggerWorkflowStageCallJob).with(
      candidate_assignment_id: assignment.id, workflow_stage_code: 'verified', request_id: 'req-1'
    )
  end

  it 'enqueues the job for every destination stage, not only ones with other side effects' do
    other_stage = WorkflowStage.find_by!(code: 'documents_pending')

    expect do
      described_class.call(
        history_entry: create(:candidate_stage_history, candidate_assignment: assignment,
                                                        to_workflow_stage: other_stage),
        context: { candidate:, assignment:, destination_stage: other_stage, current_stage: nil },
        transition: { request_id: 'req-2', transitioned_at: Time.current, evidence: {} }
      )
    end.to have_enqueued_job(AiCalls::TriggerWorkflowStageCallJob).with(
      candidate_assignment_id: assignment.id, workflow_stage_code: 'documents_pending', request_id: 'req-2'
    )
  end
end
