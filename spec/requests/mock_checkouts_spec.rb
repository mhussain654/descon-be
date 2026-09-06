# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /mock_checkout', type: :request do
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

    expect(response).to have_http_status(:ok)
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
end
