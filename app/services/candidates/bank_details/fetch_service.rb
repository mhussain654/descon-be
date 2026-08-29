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
        return @bank_detail if defined?(@bank_detail)

        @bank_detail = current_assignment_record
      end

      def current_assignment
        @current_assignment ||= @candidate.current_assignment
      end

      def current_assignment_record
        assignment = current_assignment
        return if assignment.blank?

        assignment.candidate_bank_details.current_version.first
      end
    end
  end
end
