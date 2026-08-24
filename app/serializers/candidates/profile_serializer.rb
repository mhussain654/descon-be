# frozen_string_literal: true

module Candidates
  # Mirrors Users::ProfileSerializer's shape/rationale: only public_id is
  # exposed as `id`, never the internal database id.
  class ProfileSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      {
        id: @candidate.public_id,
        full_name: @candidate.full_name,
        preferred_locale: @candidate.preferred_locale
      }
    end
  end
end
