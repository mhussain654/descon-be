# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::ConversionQuery do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  it 'reports count and percentage reaching each funnel stage, using current stage position as a floor' do
    registered = stage('registered', 1)
    documents_uploaded = stage('documents_uploaded', 3)
    verified = stage('verified', 5)
    mobilized = stage('mobilized', 15)

    create(:candidate_assignment, current_workflow_stage: registered)
    create(:candidate_assignment, current_workflow_stage: documents_uploaded)
    create(:candidate_assignment, current_workflow_stage: verified)
    create(:candidate_assignment, current_workflow_stage: mobilized)

    result = described_class.call

    expect(result).to eq(
      [
        { code: 'documents_uploaded', count: 3, percentage: 75.0 },
        { code: 'verified', count: 2, percentage: 50.0 },
        { code: 'mobilized', count: 1, percentage: 25.0 }
      ]
    )
  end

  it 'returns zero counts and zero percentages when there are no candidates' do
    stage('documents_uploaded', 3)
    stage('verified', 5)
    stage('mobilized', 15)

    result = described_class.call

    expect(result).to eq(
      [
        { code: 'documents_uploaded', count: 0, percentage: 0.0 },
        { code: 'verified', count: 0, percentage: 0.0 },
        { code: 'mobilized', count: 0, percentage: 0.0 }
      ]
    )
  end
end
