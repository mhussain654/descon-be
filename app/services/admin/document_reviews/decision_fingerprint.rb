# frozen_string_literal: true

require 'digest'

module Admin
  module DocumentReviews
    class DecisionFingerprint < ApplicationService
      # See DecisionService's identical rubocop:disable rationale: one
      # required identifier trio plus 3 independent optional overrides,
      # each already fingerprinted the same way -- no shared value object.
      # rubocop:disable Metrics/ParameterLists
      def initialize(action:, document:, request:, rejection_reason: nil, issued_on: nil, expires_on: nil)
        # rubocop:enable Metrics/ParameterLists
        @action = action.to_s
        @document = document
        @rejection_reason = rejection_reason.to_s.strip
        @request = request
        @issued_on = issued_on.to_s.strip
        @expires_on = expires_on.to_s.strip
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [@request.request_method, @request.path, @action, @document.public_id, @rejection_reason, @issued_on,
         @expires_on]
      end
    end
  end
end
