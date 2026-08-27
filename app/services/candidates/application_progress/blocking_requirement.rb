# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    BlockingRequirement = Data.define(:name, :reason, :requirement_code)
  end
end
