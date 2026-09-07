# frozen_string_literal: true

# Stands in for the mock payment provider's own hosted checkout page (see
# Payments::Providers::MockHostedCheckoutAdapter#create_checkout_session,
# which points candidates at this controller instead of a real external
# domain) -- so PAYMENT_PROVIDER=mock_hosted_checkout can be exercised
# end-to-end from a real browser/WebView, not only from RSpec. Never
# available in production, the one environment where a real provider is
# always required.
class MockCheckoutsController < ApplicationController
  before_action :ensure_not_production!

  def show
    @payment = Payment.find_by!(provider_order_id: params.require(:orderid), provider_code: 'mock_hosted_checkout')
    # Every interpolated value in checkout_page goes through ERB::Util.html_escape;
    # the surrounding markup is a static, developer-authored template with no
    # unescaped user input, so tagging it html_safe here is deliberate, not an oversight.
    render html: checkout_page.html_safe, layout: false # rubocop:disable Rails/OutputSafety
  end

  private

  def ensure_not_production!
    head :not_found if Rails.env.production?
  end

  def adapter
    @adapter ||= Payments::Providers::MockHostedCheckoutAdapter.new(configuration: Payments::Configuration.new)
  end

  def return_url_for(outcome)
    query = URI.encode_www_form(adapter.simulated_return_params(payment: @payment, outcome:))
    "#{api_v1_payments_return_url(provider_code: 'mock_hosted_checkout')}?#{query}"
  end

  def checkout_page
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Mock Hosted Checkout</title>
        <style>
          body { font-family: -apple-system, sans-serif; max-width: 480px; margin: 4rem auto; padding: 0 1.5rem; color: #1b2724; }
          h1 { font-size: 1.25rem; }
          .amount { font-size: 2rem; font-weight: 600; margin: 1rem 0; }
          dl { display: grid; grid-template-columns: auto 1fr; gap: 0.4rem 1rem; font-size: 0.9rem; color: #4a5652; }
          .actions { margin-top: 2rem; display: flex; flex-direction: column; gap: 0.75rem; }
          a.button { display: block; text-align: center; padding: 0.85rem; border-radius: 8px; text-decoration: none; font-weight: 600; }
          a.pay { background: #0e5c55; color: #fff; }
          a.fail { background: #f3e2dd; color: #8e3a30; }
          a.cancel { background: #eee; color: #333; }
        </style>
      </head>
      <body>
        <p>This is a stand-in for a real payment provider's hosted page -- used only because
        <code>PAYMENT_PROVIDER=mock_hosted_checkout</code> is active.</p>
        <h1>Descon Manpower -- Onboarding Fee</h1>
        <div class="amount">#{ERB::Util.html_escape(@payment.amount)} #{ERB::Util.html_escape(@payment.currency_code)}</div>
        <dl>
          <dt>Order ID</dt><dd>#{ERB::Util.html_escape(@payment.provider_order_id)}</dd>
        </dl>
        <div class="actions">
          <a class="button pay" href="#{ERB::Util.html_escape(return_url_for('success'))}">Simulate successful payment</a>
          <a class="button fail" href="#{ERB::Util.html_escape(return_url_for('failed'))}">Simulate failed payment</a>
          <a class="button cancel" href="#{ERB::Util.html_escape(return_url_for('cancelled'))}">Simulate cancelling</a>
        </div>
      </body>
      </html>
    HTML
  end
end
