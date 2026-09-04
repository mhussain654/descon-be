# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ReconciliationJob do
  it 'runs reconciliation for the given ISO8601 run_date' do
    allow(Payments::ReconciliationService).to receive(:call)

    described_class.perform_now('2026-09-01')

    expect(Payments::ReconciliationService).to have_received(:call).with(run_date: Date.new(2026, 9, 1))
  end

  it 'defaults to reconciling the current date when no run_date is given' do
    allow(Payments::ReconciliationService).to receive(:call)

    travel_to(Time.zone.local(2026, 9, 3, 12, 0, 0)) { described_class.perform_now }

    expect(Payments::ReconciliationService).to have_received(:call).with(run_date: Date.new(2026, 9, 3))
  end
end
