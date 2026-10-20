# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::BulkCalls::EligibleCandidatesQuery do
  let(:voice) { create(:robocall_voice) }

  def query(params = nil, **options)
    described_class.new(scope: Candidate.all, params: ActionController::Parameters.new(params || options), voice:)
  end

  def verified = { filter: { status: 'verified' } }

  it 'requires a workflow stage' do
    expect { query.call.to_a }.to raise_error(InvalidQueryParameterError)
    expect { query(filter: { status: ' ' }).summary }.to raise_error(InvalidQueryParameterError)
  end

  it 'lists only the active candidates at that stage' do
    at_stage, = candidate_at('verified')
    candidate_at('fee_paid')
    candidate_at('verified', active: false)

    expect(query(verified).call).to contain_exactly(at_stage)
  end

  it 'narrows by the candidate list filters (country, project, craft)' do
    qatar, = candidate_at('verified')
    other, other_assignment = candidate_at('verified')
    other_assignment.update!(country: create(:country, code: 'oman'))

    result = query(filter: { status: 'verified', country_code: 'oman' }).call

    expect(result).to contain_exactly(other)
    expect(result).not_to include(qatar)
  end

  describe 'who counts as already called' do
    it 'counts a candidate with a call made with this voice, but not one made with another voice' do
      called, called_assignment = candidate_at('verified')
      other_voice_candidate, other_assignment = candidate_at('verified')
      untouched, = candidate_at('verified')
      call_with_voice(called_assignment, voice)
      call_with_voice(other_assignment, create(:robocall_voice))

      expect(query(verified).call).to contain_exactly(other_voice_candidate, untouched)
      expect(query(verified.merge(called: 'called')).call).to contain_exactly(called)
      expect(query(verified.merge(called: 'all')).call).to contain_exactly(called, other_voice_candidate, untouched)
    end

    it 'counts a candidate still queued in a bulk batch, but not one whose item was skipped or failed' do
      queued, queued_assignment = candidate_at('verified')
      skipped, skipped_assignment = candidate_at('verified')
      batch = create(:bulk_call_batch, robocall_voice: voice)
      create(:bulk_call_batch_item, bulk_call_batch: batch, candidate: queued, candidate_assignment: queued_assignment)
      create(:bulk_call_batch_item, bulk_call_batch: batch, candidate: skipped,
                                    candidate_assignment: skipped_assignment, status: 'skipped',
                                    skip_reason: 'stage_changed')

      expect(query(verified).call).to contain_exactly(skipped)
    end
  end

  it 'reports how many match, were called and remain' do
    _, first = candidate_at('verified')
    candidate_at('verified')
    candidate_at('verified')
    call_with_voice(first, voice)

    expect(query(verified).summary).to eq(matching: 3, called: 1, remaining: 2)
  end

  it 'picks the next candidates to call in a stable order, up to the limit' do
    people = Array.new(3) { candidate_at('verified').first }
    _, assignment = candidate_at('verified')
    call_with_voice(assignment, voice)

    picked = query(verified).next_candidates(2).to_a

    expect(picked.size).to eq(2)
    expect(picked).to all(satisfy { |candidate| people.include?(candidate) })
    expect(query(verified).next_candidates(2).to_a).to eq(picked)
  end

  it 'paginates and reports the totals' do
    Array.new(3) { candidate_at('verified') }
    list = query(verified.merge(page: { number: 2, size: 2 }))

    expect(list.call.size).to eq(1)
    expect(list.pagination).to eq(page: 2, per_page: 2, total_count: 3, total_pages: 2)
  end

  it 'rejects an oversized or invalid page, and an unknown called value' do
    expect { query(verified.merge(page: { size: 101 })).call }.to raise_error(InvalidQueryParameterError)
    expect { query(verified.merge(page: { number: 'x' })).call }.to raise_error(InvalidQueryParameterError)
    expect { query(verified.merge(called: 'maybe')).call }.to raise_error(InvalidQueryParameterError)
  end

  it 'exposes the stage and the narrowing filters for the batch record' do
    list = query(filter: { status: 'verified', country_code: 'qatar', project_code: '' })

    expect(list.stage_code).to eq('verified')
    expect(list.narrowing_filters).to eq('country_code' => 'qatar')
  end

  it 'has no narrowing filters when the filter param is absent' do
    expect(query.narrowing_filters).to eq({})
  end
end
