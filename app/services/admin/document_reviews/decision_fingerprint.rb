# frozen_string_literal: true

require 'digest'

module Admin
  module DocumentReviews
    class DecisionFingerprint < ApplicationService
      def initialize(action:, document:, request:, rejection_reason: nil)
        @action = action.to_s
        @document = document
        @rejection_reason = rejection_reason.to_s.strip
        @request = request
      end

      def call
        Digest::SHA256.hexdigest(
          [
            @request.request_method,
            @request.path,
            @action,
            @document.public_id,
            @rejection_reason
          ].join("\n")
        )
      end
    end
  end
end
