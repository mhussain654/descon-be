# frozen_string_literal: true

module Candidates
  module BankDetails
    class AccountNumberMasker < ApplicationService
      def initialize(account_number:)
        @account_number = account_number.to_s.gsub(/\s+/, '')
      end

      def call
        return '****' if @account_number.blank?
        return '*' * @account_number.length if @account_number.length <= 4

        "#{'*' * (@account_number.length - 4)}#{@account_number.last(4)}"
      end
    end
  end
end
