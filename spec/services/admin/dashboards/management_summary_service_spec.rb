# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Dashboards::ManagementSummaryService do
  it 'assembles the conversion funnel, outcome tracking, mobilization and trend sections' do
    registered_stage = WorkflowStage.find_or_create_by!(code: 'registered') do |record|
      record.position = 1
      record.system_defined = true
    end
    create(:candidate_assignment, current_workflow_stage: registered_stage)

    result = described_class.call

    expect(result.fetch(:conversion_funnel)).to be_an(Array)
    expect(result.fetch(:outcome_tracking)).to eq(
      rejected_documents: 0, qvc_re_medical: 0, qvc_rejected: 0, qvc_no_show: 0, visa_rejected: 0
    )
    expect(result.fetch(:mobilization)).to eq(by_country: [], by_project: [])
    expect(result.fetch(:mobilization_trend)).to eq([])
  end

  it 'passes through the requested trend granularity' do
    allow(Admin::Reports::TrendQuery).to receive(:call).and_call_original

    described_class.new(trend_granularity: 'daily').call

    expect(Admin::Reports::TrendQuery).to have_received(:call).with(granularity: 'daily')
  end
end
