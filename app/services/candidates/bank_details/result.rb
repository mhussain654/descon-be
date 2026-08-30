# frozen_string_literal: true

module Candidates
  module BankDetails
    Result = Struct.new(:bank_detail, :replaced, keyword_init: true) do
      def created?
        !replaced
      end
    end
  end
end
