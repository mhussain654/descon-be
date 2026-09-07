# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::CraftSummaryQuery do
  def mobilized_stage
    WorkflowStage.find_or_create_by!(code: 'mobilized') do |record|
      record.position = 15
      record.system_defined = true
    end
  end

  def registered_stage
    WorkflowStage.find_or_create_by!(code: 'registered') do |record|
      record.position = 1
      record.system_defined = true
    end
  end

  it 'reports total and mobilized counts per craft, largest total first' do
    electrician = create(:craft)
    plumber = create(:craft)
    create(:candidate_assignment, craft: electrician, current_workflow_stage: mobilized_stage)
    create(:candidate_assignment, craft: electrician, current_workflow_stage: registered_stage)
    create(:candidate_assignment, craft: plumber, current_workflow_stage: registered_stage)
    create(:candidate_assignment, craft: plumber, current_workflow_stage: registered_stage)
    create(:candidate_assignment, craft: plumber, current_workflow_stage: registered_stage)

    result = described_class.call

    expect(result).to eq(
      [
        { code: plumber.code, name: plumber.name_for, total: 3, mobilized: 0 },
        { code: electrician.code, name: electrician.name_for, total: 2, mobilized: 1 }
      ]
    )
  end

  it 'omits crafts with no current assignment' do
    create(:craft)

    expect(described_class.call).to eq([])
  end
end
