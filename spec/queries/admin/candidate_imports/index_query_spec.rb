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
end
