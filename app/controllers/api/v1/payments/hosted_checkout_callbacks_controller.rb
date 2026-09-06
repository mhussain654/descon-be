# frozen_string_literal: true

module Api
  module V1
    module Payments
      # Receives server-to-server payment notifications from a hosted checkout provider (e.g. KuickPay)
      # and applies them to the matching payment and candidate workflow.
      class HostedCheckoutCallbacksController < ApplicationController
        # Processes an inbound provider callback notification and returns the updated payment/workflow state.
        def create
          result = ::Payments::NotificationProcessor.call(
            provider_code: params.expect(:provider_code),
            event_source: 'callback',
            params: notification_params.to_h,
            request_id: request.request_id
          )

          render_success(data: serialized_result(result))
        end

        private

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
