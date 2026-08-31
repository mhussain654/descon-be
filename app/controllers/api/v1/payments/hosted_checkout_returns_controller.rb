# frozen_string_literal: true

module Api
  module V1
    module Payments
      class HostedCheckoutReturnsController < ApplicationController
        def show
          render_notification_result
        end

        def create
          render_notification_result
        end

        private

        def render_notification_result
          result = ::Payments::NotificationProcessor.call(
            provider_code: params.expect(:provider_code),
            event_source: 'return',
            params: notification_params.to_h,
            request_id: request.request_id
          )

          render_success(data: serialized_result(result))
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
