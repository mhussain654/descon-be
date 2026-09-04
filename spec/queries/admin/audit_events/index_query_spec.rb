# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AuditEvents::IndexQuery do
  let(:scope) { AuditEvent.order(nil) }

  def query(params = {})
    described_class.new(scope:, params: ActionController::Parameters.new(params))
  end

  def event_for(actor: create(:user), action_code: 'candidate_document_verified', entity_type: 'CandidateDocument',
                occurred_at: Time.current, candidate: nil)
    assignment = create(:candidate_assignment, candidate: candidate || create(:candidate))
    create(:audit_event, actor:, candidate: assignment.candidate, candidate_assignment: assignment,
                         action_code:, entity_type:, entity_id: assignment.id, occurred_at:)
  end

  it 'defaults to occurred_at descending' do
    older = event_for(occurred_at: 2.days.ago)
    newer = event_for(occurred_at: 1.hour.ago)

    result = query.call

    expect(result.map(&:id)).to eq([newer.id, older.id])
  end

  it 'filters by actor' do
    actor = create(:user)
    other = create(:user)
    mine = event_for(actor:)
    event_for(actor: other)

    result = query(filter: { actor: actor.public_id }).call

    expect(result.map(&:id)).to eq([mine.id])
  end

  it 'rejects an unknown actor public_id' do
    expect { query(filter: { actor: 'not-a-real-id' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.actor') }
  end

  it 'filters by a comma-separated action list' do
    verified = event_for(action_code: 'candidate_document_verified')
    event_for(action_code: 'candidate_document_rejected')
    payment = event_for(action_code: 'payment_corrected', entity_type: 'Payment')

    result = query(filter: { action: 'candidate_document_verified,payment_corrected' }).call

    expect(result.map(&:id)).to contain_exactly(verified.id, payment.id)
  end

  it 'filters by entity_type' do
    document_event = event_for(entity_type: 'CandidateDocument')
    event_for(entity_type: 'Payment', action_code: 'payment_corrected')

    result = query(filter: { entity_type: 'CandidateDocument' }).call

    expect(result.map(&:id)).to eq([document_event.id])
  end

  it 'filters by candidate' do
    candidate = create(:candidate)
    mine = event_for(candidate:)
    event_for

    result = query(filter: { candidate: candidate.public_id }).call

    expect(result.map(&:id)).to eq([mine.id])
  end

  it 'rejects an unknown candidate public_id' do
    expect { query(filter: { candidate: 'not-a-real-id' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.candidate') }
  end

  it 'filters by an occurred_at date range' do
    in_range = event_for(occurred_at: Time.zone.parse('2026-06-15 10:00:00'))
    event_for(occurred_at: Time.zone.parse('2026-01-01 10:00:00'))

    result = query(filter: { occurred_from: '2026-06-01', occurred_to: '2026-06-30' }).call

    expect(result.map(&:id)).to eq([in_range.id])
  end

  it 'rejects occurred_from after occurred_to' do
    expect { query(filter: { occurred_from: '2026-06-30', occurred_to: '2026-06-01' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.occurred_to') }
  end

  it 'rejects a malformed date' do
    expect { query(filter: { occurred_from: 'not-a-date' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.occurred_from') }
  end

  it 'rejects an unsupported filter' do
    expect { query(filter: { bogus: 'x' }).call }
      .to raise_error(UnsupportedFilterError) { |error| expect(error.field).to eq('filter.bogus') }
  end

  it 'rejects an unsupported sort field' do
    expect { query(sort: 'bogus').call }
      .to raise_error(UnsupportedSortError) { |error| expect(error.field).to eq('sort.bogus') }
  end

  it 'paginates and reports metadata' do
    3.times { event_for }

    index_query = query(page: { number: 1, size: 2 })
    result = index_query.call

    expect(result.size).to eq(2)
    expect(index_query.pagination).to eq(page: 1, per_page: 2, total_count: 3, total_pages: 2)
  end

  it 'rejects a page size above the maximum' do
    expect { query(page: { size: 101 }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('page.size') }
  end
end
