# frozen_string_literal: true

module Api
  module V1
    module Payments
      class HostedCheckoutCallbacksController < ApplicationController
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
