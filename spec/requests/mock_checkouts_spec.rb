# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /mock_checkout', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['FRONTEND_PAYMENT_RETURN_URL'] = 'https://app.example.test/payment/pending'
    example.run
  ensure
    ENV.replace(original_env)
  end

  let(:payment) do
    create(
      :payment,
      provider_order_id: 'PAY-ORDER-123',
      provider_code: 'mock_hosted_checkout',
      amount: BigDecimal('1500.00'),
      currency_code: 'PKR',
      status_code: 'checkout_pending',
      paid_at: nil
    )
  end

  it 'renders an HTML page showing the amount and order id, linking to each simulated outcome' do
    get mock_checkout_path(orderid: payment.provider_order_id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('1500.0')
    expect(response.body).to include('PKR')
    expect(response.body).to include('PAY-ORDER-123')
    expect(response.body).to include('Simulate successful payment')
    expect(response.body).to include('Simulate failed payment')
    expect(response.body).to include('Simulate cancelling')
  end

  it 'links to a return URL that a real return request can process end-to-end' do
    get mock_checkout_path(orderid: payment.provider_order_id)

    success_href = response.body[/href="([^"]*status=SUCCESS[^"]*)"/, 1]
    expect(success_href).to be_present

    get CGI.unescapeHTML(success_href)

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to('https://app.example.test/payment/pending')
    expect(payment.reload).to be_paid
  end

  it 'returns not found for an unknown order id' do
    get mock_checkout_path(orderid: 'no-such-order')

    expect(response).to have_http_status(:not_found)
  end

  it 'is unavailable in production' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))

    get mock_checkout_path(orderid: payment.provider_order_id)

    expect(response).to have_http_status(:not_found)
  end

  it 'is unavailable in a shared staging environment -- not just production' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('staging'))

    get mock_checkout_path(orderid: payment.provider_order_id)

    expect(response).to have_http_status(:not_found)
  end

  it 'requires no authentication to reach the page (the signed return link is what actually moves payment state)' do
    # No session/auth headers are set anywhere in this spec -- this
    # documents that fact rather than asserting a login requirement that
    # doesn't exist. The real control is environment-gating (verified
    # above), since this action is designed to be reachable by any local
    # developer/CI run without a staff session.
    get mock_checkout_path(orderid: payment.provider_order_id)

    expect(response).to have_http_status(:ok)
  end

  it 'is idempotent when the same signed success link is replayed' do
    get mock_checkout_path(orderid: payment.provider_order_id)
    success_href = CGI.unescapeHTML(response.body[/href="([^"]*status=SUCCESS[^"]*)"/, 1])

    get success_href
    get success_href

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to('https://app.example.test/payment/pending')
    expect(payment.reload).to be_paid
  end

  it 'rejects a tampered signed return link (amount changed after signing)' do
    get mock_checkout_path(orderid: payment.provider_order_id)
    success_href = CGI.unescapeHTML(response.body[/href="([^"]*status=SUCCESS[^"]*)"/, 1])
    tampered_href = success_href.sub(/amount=[^&]*/, 'amount=1.00')

    get tampered_href

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to('https://app.example.test/payment/pending')
    expect(payment.reload).not_to be_paid
  end

  it 'rejects a signed return link replayed against a different order id' do
    other_payment = create(:payment, provider_order_id: 'PAY-ORDER-OTHER', provider_code: 'mock_hosted_checkout',
                                     status_code: 'checkout_pending', paid_at: nil)
    get mock_checkout_path(orderid: payment.provider_order_id)
    success_href = CGI.unescapeHTML(response.body[/href="([^"]*status=SUCCESS[^"]*)"/, 1])
    redirected_href = success_href.sub(payment.provider_order_id, other_payment.provider_order_id)

    get redirected_href

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to('https://app.example.test/payment/pending')
    expect(other_payment.reload).not_to be_paid
  end
end
