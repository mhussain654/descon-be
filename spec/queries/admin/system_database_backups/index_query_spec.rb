# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SystemDatabaseBackups::IndexQuery do
  it 'returns backups most-recent-first with pagination metadata' do
    older = create(:system_database_backup, taken_at: 2.days.ago)
    newer = create(:system_database_backup, taken_at: 1.day.ago)

    query = described_class.new(scope: SystemDatabaseBackup.all, params: {})
    results = query.call

    expect(results.to_a).to eq([newer, older])
    expect(query.pagination).to include(page: 1, per_page: 20, total_count: 2)
  end

  it 'paginates according to page.number and page.size' do
    create_list(:system_database_backup, 3)

    query = described_class.new(scope: SystemDatabaseBackup.all, params: { page: { number: '2', size: '2' } })
    results = query.call

    expect(results.size).to eq(1)
    expect(query.pagination).to include(page: 2, per_page: 2, total_pages: 2)
  end

  it 'raises InvalidQueryParameterError for a page size over the maximum' do
    query = described_class.new(scope: SystemDatabaseBackup.all, params: { page: { size: '101' } })

    expect { query.call }.to raise_error(InvalidQueryParameterError)
  end
end
