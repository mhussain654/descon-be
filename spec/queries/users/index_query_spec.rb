# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::IndexQuery do
  let(:scope) { User.order(nil) }

  before do
    ensure_staff_authorization_reference_data!
  end

  def query(params = {})
    described_class.new(scope:, params: ActionController::Parameters.new(params))
  end

  it 'uses the default pagination and sorting when no params are supplied' do
    older = create(:user, email: 'older@example.com', created_at: 2.days.ago)
    newer = create(:user, email: 'newer@example.com', created_at: 1.day.ago)
    index_query = query

    result = index_query.call

    expect(result.map(&:id)).to eq([newer.id, older.id])
    expect(index_query.pagination).to include(page: 1, per_page: 20, total_count: 2, total_pages: 1)
  end

  it 'filters and sorts by canonical staff state' do
    invited = create(:user, email: 'invited@example.com', staff_state: 'invited', active: false)
    suspended = create(:user, email: 'suspended@example.com', staff_state: 'suspended', active: false)
    create(:user, email: 'active@example.com', staff_state: 'active', active: true)
    index_query = query(filter: { staff_state: 'invited,suspended' }, sort: 'staff_state')

    result = index_query.call

    expect(result.map(&:id)).to eq([invited.id, suspended.id])
    expect(index_query.pagination).to include(page: 1, per_page: 20, total_count: 2, total_pages: 1)
  end

  it 'rejects malformed staff state filters' do
    expect do
      query(filter: { staff_state: 'ghost_state' }).call
    end.to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.staff_state') }
  end
end
