# frozen_string_literal: true

module Admin
  module CandidateBankDetails
    AccessResult = Struct.new(:bank_detail, :expires_at, :url, keyword_init: true)
  end
end
