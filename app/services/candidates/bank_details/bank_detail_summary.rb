# frozen_string_literal: true

module Candidates
  module BankDetails
    BankDetailSummary = Struct.new(:status, :bank_detail, keyword_init: true)
  end
end
