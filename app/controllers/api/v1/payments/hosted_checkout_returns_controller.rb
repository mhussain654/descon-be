# frozen_string_literal: true

module Api
  module V1
    module Payments
      # Handles the browser being redirected back from a hosted checkout provider (e.g. KuickPay)
      # after the candidate completes (or abandons) payment, whether the provider used GET or POST.
      #
      # Payment is made only from the mobile app, which shows the checkout in an in-app WebView and
      # closes it the moment navigation reaches this endpoint (see HostedCheckoutWebView.tsx). So
      # every outcome here -- success or any error -- is an empty 204, never a rendered JSON body
      # and never a redirect: this is an unauthenticated browser response reachable by anyone who
      # lands on the URL, so it must never expose payment/workflow data or internal error detail.
      # The app's own polled GET /candidate/payment stays the sole source of truth for the outcome.
      # This overrides ApplicationController's usual JSON error rendering for this controller only --
      # every other controller is unaffected.
      class HostedCheckoutReturnsController < ApplicationController
        rescue_from StandardError, with: :respond_after_error

        # Processes the provider's return notification (GET redirect).
        def show
          process_return
        end

        # Processes the provider's return notification (POST redirect).
        def create
          process_return
        end

        private

        # KuickPay's guide: the return redirect carries only `status`,
        # `orderid` and `sessionid` -- unsigned, "do not treat this redirect
        # as proof of payment on its own." So this never trusts those query
        # params directly; it only uses `orderid` to find which payment to
        # verify, then calls the Status API server-side (the guide's 4th
        # step) for the authoritative outcome. A missing orderid or unknown
        # payment is a silent no-op here -- the candidate's original tab
        # keeps polling GET /candidate/payment regardless.
        def process_return
          log_return_received
          payment = payment_for_return
          ::Payments::VerifyPaymentStatusService.call(payment:, request_id: request.request_id) if payment
          head :no_content
        end

        # Logs exactly what the browser return carried -- method, every
        # query/body param as received -- unconditionally and before any
        # processing, so a real sandbox return's exact payload is captured
        # even if lookup/verification below fails or finds nothing. This is
        # the definitive answer to "what does your hosted checkout return
        # redirect send back to us:" grep the log for this line.
        def log_return_received
          Rails.logger.info(
            "[Payments][#{params[:provider_code]}][return] method=#{request.method} " \
            "params=#{params.to_unsafe_h.except('controller', 'action').to_json}"
          )
        end

        def payment_for_return
          order_id = params[:orderid].to_s.presence
          return nil if order_id.blank?

          Payment.find_by(provider_code: params.expect(:provider_code), provider_order_id: order_id)
        end

        # Mirrors ApplicationController#render_unexpected_error's Pundit-verification safety
        # net and unexpected-error logging, but answers an empty 204 instead of rendering JSON.
        def respond_after_error(error)
          raise error if pundit_verification_error?(error)

          Rails.logger.error(unexpected_error_payload(error).to_json) unless error.is_a?(BaseError)
          head :no_content
        end
      end
    end
  end
end
