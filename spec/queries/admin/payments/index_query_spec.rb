# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Payments::IndexQuery do
  def params_for(hash)
    ActionController::Parameters.new(hash)
  end

  def payment_for(full_name: 'Ahmed Ali', reference_number: "DES-#{SecureRandom.hex(4).upcase}", **attrs)
    candidate = create(:candidate, full_name:)
    assignment = create(:candidate_assignment, candidate:, reference_number:)
    create(:payment, candidate_assignment: assignment, **attrs)
  end

  it 'defaults to sorting by created_at desc and paginating with the default page size' do
    older = payment_for(created_at: 2.days.ago)
    newer = payment_for(created_at: 1.day.ago)

    query = described_class.new(scope: Payment.all, params: params_for({}))
    result = query.call

    expect(result.to_a).to eq([newer, older])
    expect(query.pagination).to include(page: 1, per_page: described_class::DEFAULT_PAGE_SIZE)
  end

  it 'filters by status, provider_code, payment_type_code and currency_code' do
    matching = payment_for(status_code: 'paid', paid_at: Time.current, provider_code: 'kuickpay', currency_code: 'PKR')
    payment_for(status_code: 'checkout_pending', provider_code: 'mock_hosted_checkout')

    result = described_class.new(
      scope: Payment.all,
      params: params_for(filter: { status: 'paid', provider_code: 'kuickpay', currency_code: 'PKR' })
    ).call

    expect(result.to_a).to eq([matching])
  end

  it 'filters by a created_from/created_to date range' do
    in_range = payment_for(created_at: Time.zone.local(2026, 6, 15, 10))
    payment_for(created_at: Time.zone.local(2026, 5, 1, 10))
    payment_for(created_at: Time.zone.local(2026, 7, 1, 10))

    result = described_class.new(
      scope: Payment.all,
      params: params_for(filter: { created_from: '2026-06-01', created_to: '2026-06-30' })
    ).call

    expect(result.to_a).to eq([in_range])
  end

  it 'rejects an invalid date range where created_from is after created_to' do
    expect do
      described_class.new(
        scope: Payment.all,
        params: params_for(filter: { created_from: '2026-06-30', created_to: '2026-06-01' })
      ).call
    end.to raise_error(InvalidQueryParameterError)
  end

  it 'rejects an unsupported filter key' do
    expect do
      described_class.new(scope: Payment.all, params: params_for(filter: { bogus: 'x' })).call
    end.to raise_error(UnsupportedFilterError)
  end

  describe 'reconciliation_state filter' do
    it "'open' returns only payments with an open finding" do
      open_payment = payment_for
      create(:payment_reconciliation_finding, payment: open_payment, state_code: 'open')
      payment_for # clean, no findings

      result = described_class.new(scope: Payment.all,
                                   params: params_for(filter: { reconciliation_state: 'open' })).call

      expect(result.to_a).to eq([open_payment])
    end

    it "'resolved' returns only payments whose findings are all resolved" do
      resolved_payment = payment_for
      create(:payment_reconciliation_finding, payment: resolved_payment, state_code: 'resolved',
                                              resolved_at: Time.current, resolved_by: create(:user),
                                              resolution_note: 'ok')
      open_payment = payment_for
      create(:payment_reconciliation_finding, payment: open_payment, state_code: 'open')

      result = described_class.new(scope: Payment.all,
                                   params: params_for(filter: { reconciliation_state: 'resolved' })).call

      expect(result.to_a).to eq([resolved_payment])
    end

    it "'clean' returns only payments with no findings at all" do
      clean_payment = payment_for
      flagged_payment = payment_for
      create(:payment_reconciliation_finding, payment: flagged_payment)

      result = described_class.new(scope: Payment.all,
                                   params: params_for(filter: { reconciliation_state: 'clean' })).call

      expect(result.to_a).to eq([clean_payment])
    end
  end

  it 'searches by candidate name, assignment reference number and external_reference' do
    by_name = payment_for(full_name: 'Zubair Khan')
    by_reference = payment_for(reference_number: 'DES-SEARCHABLE')
    by_external_ref = payment_for(status_code: 'paid', paid_at: Time.current, external_reference: 'KP-77889900')
    payment_for(full_name: 'Someone Else')

    expect(described_class.new(scope: Payment.all, params: params_for(search: 'Zubair')).call.to_a).to eq([by_name])
    expect(described_class.new(scope: Payment.all,
                               params: params_for(search: 'SEARCHABLE')).call.to_a).to eq([by_reference])
    expect(described_class.new(scope: Payment.all,
                               params: params_for(search: '77889900')).call.to_a).to eq([by_external_ref])
  end

  it 'sorts by an allowed field and direction' do
    small = payment_for(amount: 500)
    large = payment_for(amount: 2500)

    ascending = described_class.new(scope: Payment.all, params: params_for(sort: 'amount')).call
    descending = described_class.new(scope: Payment.all, params: params_for(sort: '-amount')).call

    expect(ascending.to_a).to eq([small, large])
    expect(descending.to_a).to eq([large, small])
  end

  it 'rejects an unsupported sort field' do
    expect do
      described_class.new(scope: Payment.all, params: params_for(sort: 'candidate_name')).call
    end.to raise_error(UnsupportedSortError)
  end

  it 'paginates with page[number]/page[size] and reports pagination metadata' do
    5.times { payment_for }

    query = described_class.new(scope: Payment.all, params: params_for(page: { number: 2, size: 2 }))
    result = query.call

    expect(result.count).to eq(2)
    expect(query.pagination).to eq(page: 2, per_page: 2, total_count: 5, total_pages: 3)
  end

  it 'rejects a page size above MAX_PAGE_SIZE' do
    expect do
      described_class.new(scope: Payment.all,
                          params: params_for(page: { size: described_class::MAX_PAGE_SIZE + 1 })).call
    end.to raise_error(InvalidQueryParameterError)
  end
end
