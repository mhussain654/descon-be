# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateImports::IndexQuery do
  def params(filter: {}, page: {})
    ActionController::Parameters.new(filter:, page:)
  end

  it 'filters import history by status, actor, creation range, and template version' do
    actor = create(:user)
    other_actor = create(:user)
    matching = create(:candidate_import_batch, actor:, status: 'failed', template_version: 'v2')
    matching.update!(created_at: Time.zone.parse('2026-09-01 12:00:00 UTC'))
    create(:candidate_import_batch, actor: other_actor, status: 'failed', template_version: 'v2')
    create(:candidate_import_batch, actor:, status: 'completed', template_version: 'v1')

    result = described_class.new(
      scope: CandidateImportBatch.all,
      params: params(filter: {
                       status: 'failed', actor_id: actor.public_id, template_version: 'v2',
                       created_from: '2026-09-01', created_to: '2026-09-01'
                     })
    ).call

    expect(result).to contain_exactly(matching)
  end

  it 'paginates deterministically and rejects malformed filters' do
    create_list(:candidate_import_batch, 2)
    query = described_class.new(scope: CandidateImportBatch.all, params: params(page: { number: '2', size: '1' }))

    expect(query.call.size).to eq(1)
    expect(query.pagination).to include(page: 2, per_page: 1, total_count: 2)

    expect do
      described_class.new(scope: CandidateImportBatch.all, params: params(filter: { created_from: 'not-a-date' })).call
    end.to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.created_from') }
  end

  describe '#summary' do
    it 'returns zero-filled counts per batch status' do
      create(:candidate_import_batch, status: 'completed')
      create_list(:candidate_import_batch, 2, status: 'failed')

      query = described_class.new(scope: CandidateImportBatch.all, params: params)

      expect(query.summary).to eq(
        [
          { code: 'queued', count: 0 },
          { code: 'processing', count: 0 },
          { code: 'completed', count: 1 },
          { code: 'partial', count: 0 },
          { code: 'failed', count: 2 },
          { code: 'invalidated', count: 0 }
        ]
      )
    end

    it 'excludes the status filter itself, so counts describe what selecting another status chip would show' do
      actor = create(:user)
      create(:candidate_import_batch, actor:, status: 'completed')
      create(:candidate_import_batch, actor:, status: 'failed')
      create(:candidate_import_batch, status: 'failed')

      query = described_class.new(
        scope: CandidateImportBatch.all,
        params: params(filter: { actor_id: actor.public_id, status: 'completed' })
      )

      summary = query.summary
      expect(summary.find { |row| row[:code] == 'completed' }).to eq(code: 'completed', count: 1)
      expect(summary.find { |row| row[:code] == 'failed' }).to eq(code: 'failed', count: 1)
    end
  end
end
