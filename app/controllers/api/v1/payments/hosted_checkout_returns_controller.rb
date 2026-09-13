# frozen_string_literal: true

module Api
  module V1
    module Payments
      # Handles the browser being redirected back from a hosted checkout provider (e.g. KuickPay)
      # after the candidate completes (or abandons) payment, whether the provider used GET or POST.
      #
      # Every outcome here -- success or any error -- ends in a redirect to the frontend's
      # unauthenticated payment-pending page, never a rendered JSON body. This is an
      # unauthenticated browser response reachable by anyone who lands on the URL, so it
      # must never expose payment/workflow data or internal error detail; the original
      # tab's polled GET /candidate/payment stays the sole source of truth for outcome
      # (see PaymentPanel.tsx). This overrides ApplicationController's usual JSON error
      # rendering for this controller only -- every other controller is unaffected.
      class HostedCheckoutReturnsController < ApplicationController
        rescue_from StandardError, with: :redirect_after_error

        # Processes the provider's return notification (GET redirect).
        def show
          process_return
        end

        # Processes the provider's return notification (POST redirect).
        def create
          process_return
        end

        private

        def process_return
          ::Payments::NotificationProcessor.call(
            provider_code: params.expect(:provider_code),
            event_source: 'return',
            params: notification_params.to_h,
            request_id: request.request_id
          )
          redirect_to_frontend_pending
        end

        # Mirrors ApplicationController#render_unexpected_error's Pundit-verification safety
        # net and unexpected-error logging, but redirects instead of rendering JSON.
        def redirect_after_error(error)
          raise error if pundit_verification_error?(error)

          Rails.logger.error(unexpected_error_payload(error).to_json) unless error.is_a?(BaseError)
          redirect_to_frontend_pending
        end

        # Bare redirect -- no status/outcome query params, so there is nothing here for the
        # frontend to trust or distrust; it only tells the candidate to go back to their
        # original tab, which keeps polling for the authoritative outcome. Never raises: if
        # the frontend URL is unconfigured, this method is also the one called from the
        # StandardError rescue itself, so it must not be able to trigger a second,
        # unrescued raise -- fall back to an empty response instead.
        def redirect_to_frontend_pending
          url = frontend_return_url
          return head(:no_content) if url.blank?

          redirect_to url, allow_other_host: true, status: redirect_status
        end

        def frontend_return_url
          url = ::Payments::Configuration.new.frontend_payment_return_url
          Rails.logger.error('FRONTEND_PAYMENT_RETURN_URL is not configured') if url.blank?
          url
        end

        # :see_other for a POST return avoids the browser re-submitting the provider's
        # payload on redirect; :found is the standard code for a GET-to-GET redirect.
        def redirect_status
          request.post? ? :see_other : :found
        end

        # Allowlists the provider notification fields (order/transaction ids, amount, status, signature, etc.).
        def notification_params
          params.permit(:orderid, :transactionid, :amount, :currency, :status, :responsecode, :signature)
        end
      end
    end
  end
end
