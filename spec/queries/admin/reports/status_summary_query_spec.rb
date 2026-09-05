# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::StatusSummaryQuery do
  def stage(code)
    position = WorkflowStage::CANONICAL_STAGES.find { |entry| entry.fetch(:code) == code }.fetch(:position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  it 'zero-fills every canonical stage and counts candidates at each one' do
    registered_stage = stage('registered')
    verified_stage = stage('verified')
    create(:candidate_assignment, current_workflow_stage: registered_stage)
    create(:candidate_assignment, current_workflow_stage: registered_stage)
    create(:candidate_assignment, current_workflow_stage: verified_stage)

    result = described_class.call

    expect(result.size).to eq(WorkflowStage::CANONICAL_STAGES.size)
    expect(result.find { |row| row.fetch(:code) == 'registered' }.fetch(:count)).to eq(2)
    expect(result.find { |row| row.fetch(:code) == 'verified' }.fetch(:count)).to eq(1)
    expect(result.find { |row| row.fetch(:code) == 'mobilized' }.fetch(:count)).to eq(0)
  end

  it 'accepts a pre-scoped relation' do
    registered_stage = stage('registered')
    active = create(:candidate_assignment, current_workflow_stage: registered_stage,
                                           candidate: create(:candidate, active: true)).candidate
    create(:candidate_assignment, current_workflow_stage: registered_stage,
                                  candidate: create(:candidate, active: false))

    result = described_class.call(scope: Candidate.where(id: active.id))

    expect(result.find { |row| row.fetch(:code) == 'registered' }.fetch(:count)).to eq(1)
  end
end
