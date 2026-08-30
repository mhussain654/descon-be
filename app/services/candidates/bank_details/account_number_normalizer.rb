# frozen_string_literal: true

module Candidates
  module BankDetails
    class AccountNumberNormalizer < ApplicationService
      def initialize(account_number:)
        @account_number = account_number
      end

      def call
        @account_number.to_s.upcase.gsub(/\s+/, '').presence
      end
    end
  end
end
