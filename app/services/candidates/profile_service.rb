# frozen_string_literal: true

module Candidates
  class ProfileService < ApplicationService
    def initialize(candidate:)
      @candidate = candidate
    end

    def call
      ::Candidate.find(@candidate.id)
    end
  end
end
