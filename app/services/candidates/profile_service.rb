# frozen_string_literal: true

module Candidates
  class ProfileService < ApplicationService
    def initialize(candidate:)
      @candidate = candidate
    end

    def call
      ::Candidate.includes(profile_photo_attachment: :blob).find(@candidate.id)
    end
  end
end
