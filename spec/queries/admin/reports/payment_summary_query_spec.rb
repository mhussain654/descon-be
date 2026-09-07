# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::PaymentSummaryQuery do
  it 'zero-fills every payment status and counts payments on current assignments' do
    assignment = create(:candidate_assignment)
    create(:payment, candidate_assignment: assignment, status_code: 'paid')
    create(:payment, candidate_assignment: assignment, status_code: 'paid')
    create(:payment, candidate_assignment: assignment, status_code: 'failed')

    result = described_class.call

    expect(result).to eq(
      [
        { code: 'checkout_pending', count: 0 },
        { code: 'paid', count: 2 },
        { code: 'failed', count: 1 },
        { code: 'cancelled', count: 0 }
      ]
    )
  end

  it 'ignores payments on a superseded (non-current) assignment' do
    candidate = create(:candidate)
    stale = create(:candidate_assignment, candidate:, created_at: 2.days.ago)
    create(:candidate_assignment, candidate:, created_at: 1.hour.ago)
    create(:payment, candidate_assignment: stale, status_code: 'paid')

    result = described_class.call

    expect(result.find { |row| row.fetch(:code) == 'paid' }.fetch(:count)).to eq(0)
  end
end
