# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Dashboards::MpsSummaryService do
  it 'assembles the workflow queue, delayed cases, craft summary, mobilization and trend sections' do
    registered_stage = WorkflowStage.find_or_create_by!(code: 'registered') do |record|
      record.position = 1
      record.system_defined = true
    end
    create(:candidate_assignment, current_workflow_stage: registered_stage)

    result = described_class.call

    expect(result.fetch(:workflow_stage_queue)).to be_an(Array)
    expect(result.fetch(:delayed_cases)).to eq(delayed: 0, critical: 0)
    expect(result.fetch(:craft_summary)).to be_an(Array)
    expect(result.fetch(:mobilization)).to eq(by_country: [], by_project: [])
    expect(result.fetch(:mobilization_trend)).to eq([])
  end

  it 'passes through the requested trend granularity' do
    allow(Admin::Reports::TrendQuery).to receive(:call).and_call_original

    described_class.new(trend_granularity: 'weekly').call

    expect(Admin::Reports::TrendQuery).to have_received(:call).with(granularity: 'weekly')
  end
end
