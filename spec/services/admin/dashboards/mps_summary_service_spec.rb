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
    expect(result.fetch(:conversion_funnel).pluck(:code)).to contain_exactly('documents_uploaded', 'verified',
                                                                             'mobilized')
    expect(result.fetch(:latest_mobilization)).to be_nil
  end

  it 'includes the most recently mobilized candidate when one exists' do
    mobilized_stage = WorkflowStage.find_or_create_by!(code: 'mobilized') do |record|
      record.position = 15
      record.system_defined = true
    end
    assignment = create(:candidate_assignment)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: mobilized_stage,
                                     occurred_at: 1.day.ago)

    result = described_class.call

    expect(result.fetch(:latest_mobilization)).to include(candidate_assignment_public_id: assignment.public_id)
  end

  it 'passes through the requested trend granularity' do
    allow(Admin::Reports::TrendQuery).to receive(:call).and_call_original

    described_class.new(trend_granularity: 'weekly').call

    expect(Admin::Reports::TrendQuery).to have_received(:call).with(hash_including(granularity: 'weekly'))
  end

  it 'scopes every section to the requested country/project/craft filters' do
    country = create(:country)
    create(:candidate_assignment, country:)
    create(:candidate_assignment)

    result = described_class.call(params: ActionController::Parameters.new(filter: { country_code: country.code }))

    expect(result.fetch(:workflow_stage_queue).sum { |row| row.fetch(:count) }).to eq(1)
    expect(result.fetch(:craft_summary).sum { |row| row.fetch(:total) }).to eq(1)
  end

  it 'propagates an unknown filter code as InvalidQueryParameterError' do
    expect do
      described_class.call(params: ActionController::Parameters.new(filter: { country_code: 'not_a_real_country' }))
    end.to raise_error(InvalidQueryParameterError)
  end
end
