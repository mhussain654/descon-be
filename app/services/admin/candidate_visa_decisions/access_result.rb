# frozen_string_literal: true

module Admin
  module CandidateVisaDecisions
    AccessResult = Data.define(:decision, :expires_at, :url)
  end
end
