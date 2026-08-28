# frozen_string_literal: true

module Candidates
  module BankDetails
    class FetchService < ApplicationService
      def initialize(candidate:)
        @candidate = candidate
      end

      def call
        BankDetailSummary.new(
          status: bank_detail.present? ? bank_detail.status_code : 'missing',
          bank_detail:
        )
      end

      private

      def bank_detail
        @bank_detail ||= @candidate.current_assignment&.candidate_bank_details&.current_version&.first
      end
    end
  end
end
