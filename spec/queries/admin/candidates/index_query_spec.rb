# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::IndexQuery do
  before { ensure_canonical_workflow_stages! }

  def params_for(hash)
    ActionController::Parameters.new(hash)
  end

  def candidate_for(status_code: 'registered', **assignment_attrs)
    candidate = create(:candidate, status_code:)
    create(:candidate_assignment, candidate:, **assignment_attrs)
    candidate
  end

  it 'lists candidates with pagination metadata' do
    3.times { candidate_for }

    query = described_class.new(scope: Candidate.all, params: params_for(page: { number: 1, size: 2 }))
    result = query.call

    expect(result.size).to eq(2)
    expect(query.pagination).to include(page: 1, per_page: 2, total_count: 3)
  end

  it 'filters by status' do
    matching = candidate_for(status_code: 'fee_paid')
    candidate_for(status_code: 'registered')

    result = described_class.new(scope: Candidate.all, params: params_for(filter: { status: 'fee_paid' })).call

    expect(result.map(&:id)).to eq([matching.id])
  end

  it 'rejects an unknown status filter value' do
    expect { described_class.new(scope: Candidate.all, params: params_for(filter: { status: 'not-a-stage' })).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.status') }
  end

  describe '#summary' do
    it 'returns zero-filled counts across all 15 canonical stages' do
      candidate_for(status_code: 'registered')
      candidate_for(status_code: 'registered')
      candidate_for(status_code: 'fee_paid')

      summary = described_class.new(scope: Candidate.all, params: params_for({})).summary

      expect(summary.size).to eq(WorkflowStage::CANONICAL_STAGES.size)
      expect(summary.find { |row| row[:code] == 'registered' }).to eq(code: 'registered', count: 2)
      expect(summary.find { |row| row[:code] == 'fee_paid' }).to eq(code: 'fee_paid', count: 1)
      expect(summary.find { |row| row[:code] == 'mobilized' }).to eq(code: 'mobilized', count: 0)
    end

    it 'excludes the status filter itself, scoped by every other active filter' do
      country = create(:country)
      candidate_a = create(:candidate, status_code: 'fee_paid')
      create(:candidate_assignment, candidate: candidate_a, country:)
      candidate_b = create(:candidate, status_code: 'registered')
      create(:candidate_assignment, candidate: candidate_b, country:)
      other_candidate = create(:candidate, status_code: 'fee_paid')
      create(:candidate_assignment, candidate: other_candidate)

      summary = described_class.new(
        scope: Candidate.all, params: params_for(filter: { country_code: country.code, status: 'fee_paid' })
      ).summary

      expect(summary.find { |row| row[:code] == 'fee_paid' }).to eq(code: 'fee_paid', count: 1)
      expect(summary.find { |row| row[:code] == 'registered' }).to eq(code: 'registered', count: 1)
    end

    it 'does not double-join the current_assignments alias when a country/project/craft filter is also active' do
      country = create(:country)
      candidate_for(status_code: 'registered', country:)

      expect do
        described_class.new(scope: Candidate.all, params: params_for(filter: { country_code: country.code })).summary
      end
        .not_to raise_error
    end
  end
end
