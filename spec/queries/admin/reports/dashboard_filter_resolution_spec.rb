# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::DashboardFilterResolution do
  def params_with(filter)
    ActionController::Parameters.new(filter:)
  end

  it 'returns every candidate when no filter is given' do
    create(:candidate_assignment)

    result = described_class.call(params: ActionController::Parameters.new)

    expect(result.count).to eq(Candidate.count)
  end

  it 'filters by country_code' do
    country = create(:country)
    matching = create(:candidate_assignment, country:).candidate
    create(:candidate_assignment)

    result = described_class.call(params: params_with(country_code: country.code))

    expect(result).to contain_exactly(matching)
  end

  it 'filters by project_code' do
    project = create(:project)
    matching = create(:candidate_assignment, project:).candidate
    create(:candidate_assignment)

    result = described_class.call(params: params_with(project_code: project.code))

    expect(result).to contain_exactly(matching)
  end

  it 'filters by craft_code' do
    craft = create(:craft)
    matching = create(:candidate_assignment, craft:).candidate
    create(:candidate_assignment)

    result = described_class.call(params: params_with(craft_code: craft.code))

    expect(result).to contain_exactly(matching)
  end

  it 'combines multiple filters as AND' do
    country = create(:country)
    project = create(:project)
    matching = create(:candidate_assignment, country:, project:).candidate
    create(:candidate_assignment, country:)
    create(:candidate_assignment, project:)

    result = described_class.call(params: params_with(country_code: country.code, project_code: project.code))

    expect(result).to contain_exactly(matching)
  end

  it 'raises InvalidQueryParameterError for an unknown code' do
    expect do
      described_class.call(params: params_with(country_code: 'not_a_real_country'))
    end.to raise_error(InvalidQueryParameterError)
  end

  it 'raises UnsupportedFilterError for an unrecognized filter name' do
    expect do
      described_class.call(params: params_with(status: 'verified'))
    end.to raise_error(UnsupportedFilterError)
  end

  it 'composes safely with a query that performs its own CurrentAssignmentJoin' do
    country = create(:country)
    matching = create(:candidate_assignment, country:).candidate
    create(:candidate_assignment)

    scope = described_class.call(params: params_with(country_code: country.code))

    expect { Admin::Reports::StatusSummaryQuery.call(scope:) }.not_to raise_error
    expect(Admin::Reports::CurrentAssignmentJoin.call(scope:).pluck('candidates.id')).to eq([matching.id])
  end
end
