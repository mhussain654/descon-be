# frozen_string_literal: true

module Api
  module V1
    module Payments
      class HostedCheckoutReturnsController < ApplicationController
        def show
          process_notification_and_return_to_frontend
        end

        def create
          process_notification_and_return_to_frontend
        end

        private

        # This is where the candidate's own browser lands after the hosted
        # checkout page, not a server-to-server callback (that's
        # HostedCheckoutCallbacksController). Once the notification is
        # processed, send the browser on to the frontend rather than
        # leaving it on a bare JSON response -- the frontend's own pending
        # screen re-fetches GET /api/v1/candidate/payment for the
        # authoritative status rather than trusting anything about how it
        # got there. Falls back to rendering JSON when no frontend return
        # URL is configured, matching this endpoint's prior behavior.
        def process_notification_and_return_to_frontend
          result = process_notification
          frontend_url = ::Payments::Configuration.new.frontend_payment_return_url
          return render_success(data: serialized_result(result)) if frontend_url.blank?

          redirect_to frontend_url, allow_other_host: true
        end

        def process_notification
          ::Payments::NotificationProcessor.call(
            provider_code: params.expect(:provider_code),
            event_source: 'return',
            params: notification_params.to_h,
            request_id: request.request_id
          )
        end

        def notification_params
          params.permit(:orderid, :transactionid, :amount, :currency, :status, :responsecode, :signature)
        end

        def serialized_result(result)
          {
            payment: ::Payments::PaymentSerializer.new(result.fetch(:payment)).as_json,
            workflow: ::CandidateWorkflows::StateSerializer.new(result.fetch(:snapshot)).as_json
          }
        end
      end
    end
  end
end
