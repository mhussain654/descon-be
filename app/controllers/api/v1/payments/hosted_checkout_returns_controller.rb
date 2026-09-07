# frozen_string_literal: true

module Api
  module V1
    module Payments
      # Handles the browser being redirected back from a hosted checkout provider (e.g. KuickPay)
      # after the candidate completes (or abandons) payment, whether the provider used GET or POST.
      class HostedCheckoutReturnsController < ApplicationController
        # Processes the provider's return notification (GET redirect) and returns the resulting payment/workflow state.
        def show
          render_notification_result
        end

        # Processes the provider's return notification (POST redirect) and returns the resulting payment/workflow state.
        def create
          render_notification_result
        end

        private

        # Runs the shared return-notification processing and renders the serialized result.
        def render_notification_result
          result = ::Payments::NotificationProcessor.call(
            provider_code: params.expect(:provider_code),
            event_source: 'return',
            params: notification_params.to_h,
            request_id: request.request_id
          )

          render_success(data: serialized_result(result))
        end

        # Allowlists the provider notification fields (order/transaction ids, amount, status, signature, etc.).
        def notification_params
          params.permit(:orderid, :transactionid, :amount, :currency, :status, :responsecode, :signature)
        end

        # Serializes the processed payment and its resulting workflow snapshot.
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
