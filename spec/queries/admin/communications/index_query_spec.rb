# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Communications::IndexQuery do
  let(:scope) { Communication.order(nil) }

  def query(params = {})
    described_class.new(scope:, params: ActionController::Parameters.new(params))
  end

  it 'defaults to created_at descending' do
    older = travel_to(2.days.ago) { create(:communication) }
    newer = travel_to(1.hour.ago) { create(:communication) }

    result = query.call

    expect(result.map(&:id)).to eq([newer.id, older.id])
  end

  it 'filters by channel' do
    sms = create(:communication, channel_code: 'sms')
    create(:communication, channel_code: 'email')

    expect(query(filter: { channel: 'sms' }).call.map(&:id)).to eq([sms.id])
  end

  it 'filters by direction' do
    inbound = create(:communication, direction_code: 'inbound')
    create(:communication, direction_code: 'outbound')

    expect(query(filter: { direction: 'inbound' }).call.map(&:id)).to eq([inbound.id])
  end

  it 'filters by status' do
    failed = create(:communication, status_code: 'failed')
    create(:communication, status_code: 'sent')

    expect(query(filter: { status: 'failed' }).call.map(&:id)).to eq([failed.id])
  end

  it 'filters by candidate_assignment' do
    assignment = create(:candidate_assignment)
    mine = create(:communication, candidate_assignment: assignment)
    create(:communication)

    result = query(filter: { candidate_assignment: assignment.public_id }).call

    expect(result.map(&:id)).to eq([mine.id])
  end

  it 'rejects an unknown candidate_assignment public_id' do
    expect { query(filter: { candidate_assignment: 'not-a-real-id' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.candidate_assignment') }
  end

  it 'filters by candidate' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    mine = create(:communication, candidate_assignment: assignment)
    create(:communication)

    result = query(filter: { candidate: candidate.public_id }).call

    expect(result.map(&:id)).to eq([mine.id])
  end

  it 'rejects an unknown candidate public_id' do
    expect { query(filter: { candidate: 'not-a-real-id' }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.candidate') }
  end

  it 'filters by an occurred (created_at) date range' do
    in_range = travel_to(Time.zone.parse('2026-06-15 10:00:00')) { create(:communication) }
    travel_to(Time.zone.parse('2026-01-01 10:00:00')) { create(:communication) }

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
    3.times { create(:communication) }

    index_query = query(page: { number: 1, size: 2 })
    result = index_query.call

    expect(result.size).to eq(2)
    expect(index_query.pagination).to eq(page: 1, per_page: 2, total_count: 3, total_pages: 2)
  end

  it 'rejects a page size above the maximum' do
    expect { query(page: { size: 101 }).call }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('page.size') }
  end

  it 'does not N+1 when serializing candidate_assignment.candidate and initiated_by across many rows' do
    create(:communication)
    single_row_count = count_queries { load_and_touch_associations }

    3.times { create(:communication) }
    multi_row_count = count_queries { load_and_touch_associations }

    expect(multi_row_count).to eq(single_row_count)
  end

  def load_and_touch_associations
    query.call.to_a.each do |communication|
      communication.candidate_assignment.candidate.public_id
      communication.initiated_by&.public_id
    end
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == 'SCHEMA'

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
