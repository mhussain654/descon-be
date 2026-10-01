# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::LatestMobilizationQuery do
  def mobilized_stage
    WorkflowStage.find_or_create_by!(code: 'mobilized') do |record|
      record.position = 15
      record.system_defined = true
    end
  end

  def mobilization_event(assignment:, occurred_at:)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: mobilized_stage, occurred_at:)
  end

  it 'returns nil when nothing has been mobilized yet' do
    create(:candidate_assignment)

    expect(described_class.call).to be_nil
  end

  it 'returns the most recently mobilized candidate, enriched with country/project/craft' do
    country = create(:country)
    project = create(:project)
    craft = create(:craft)
    assignment = create(:candidate_assignment, country:, project:, craft:)
    mobilization_event(assignment:, occurred_at: 2.days.ago)
    later_assignment = create(:candidate_assignment)
    mobilization_event(assignment: later_assignment, occurred_at: 1.day.ago)

    result = described_class.call

    expect(result).to include(
      candidate_full_name: later_assignment.candidate.full_name,
      candidate_public_id: later_assignment.candidate.public_id,
      candidate_assignment_public_id: later_assignment.public_id,
      reference_number: later_assignment.reference_number
    )
    expect(result.fetch(:country_name)).to eq(later_assignment.country.name_for)
    expect(result.fetch(:project_name)).to eq(later_assignment.project.name_for)
    expect(result.fetch(:craft_name)).to eq(later_assignment.craft.name_for)
  end

  it 'scopes to the given candidate scope' do
    country = create(:country)
    matching_assignment = create(:candidate_assignment, country:)
    mobilization_event(assignment: matching_assignment, occurred_at: 2.days.ago)
    other_assignment = create(:candidate_assignment)
    mobilization_event(assignment: other_assignment, occurred_at: 1.day.ago)

    result = described_class.call(scope: Candidate.where(id: matching_assignment.candidate_id))

    expect(result.fetch(:candidate_assignment_public_id)).to eq(matching_assignment.public_id)
  end
end
