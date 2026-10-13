# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      # A newly imported candidate who hasn't started yet is simply
      # "registered": a blank candidate_status/workflow_stage_code, or a
      # "Not Registered" label in any common spelling/format (e.g. the
      # client's "Not Registred"), imports as the `registered` code. Any other
      # value is passed through as a code (trimmed, lowercased).
      module RegisteredStage
        CODE = 'registered'
        NOT_REGISTERED_PATTERN = /\Anot[\s_-]*regist(e)?red\z/

        module_function

        def normalize(raw_value)
          value = raw_value.to_s.squish.downcase
          return CODE if value.blank? || value.match?(NOT_REGISTERED_PATTERN)

          value
        end
      end
    end
  end
end
