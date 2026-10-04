# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::MobilizationQuery do
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

  # Completion is each process's own terminal stage: Ticket Handover for the
  # common process (a factory country), Mobilized for Qatar.
  it 'counts mobilized candidates grouped by country and by project, localized by name' do
    pakistan = create(:country, name_en: 'Pakistan', name_ur: 'پاکستان')
    qatar = process_country(:qatar)
    project = create(:project)
    ticket_handover = WorkflowStage.find_by!(code: 'ticket_handover')
    create(:candidate_assignment, current_workflow_stage: ticket_handover, country: pakistan, project:)
    create(:candidate_assignment, current_workflow_stage: ticket_handover, country: pakistan, project:)
    create(:candidate_assignment, current_workflow_stage: mobilized_stage, country: qatar, project:)
    create(:candidate_assignment, current_workflow_stage: ticket_handover, country: qatar, project:)
    create(:candidate_assignment, current_workflow_stage: registered_stage, country: pakistan, project:)

    result = described_class.call

    expect(result.fetch(:by_country)).to eq(
      [
        { code: pakistan.code, name: pakistan.name_for, count: 2 },
        { code: qatar.code, name: qatar.name_for, count: 1 }
      ]
    )
    expect(result.fetch(:by_project)).to eq([{ code: project.code, name: project.name_for, count: 3 }])
  end

  it 'returns empty groupings when no candidate has reached mobilized' do
    create(:candidate_assignment, current_workflow_stage: registered_stage)

    result = described_class.call

    expect(result).to eq(by_country: [], by_project: [])
  end
end
