# frozen_string_literal: true

module Candidates
  # Reads the candidate list's file number filter: one registration number
  # (`900005`) or an inclusive range (`900001-900050`, spaces allowed, either
  # order). Returns a Range, or nil when the text is neither.
  module RegistrationNumberRange
    FORMAT = /\A\s*(\d{1,15})\s*(?:-\s*(\d{1,15})\s*)?\z/

    def self.call(value)
      match = FORMAT.match(value.to_s)
      return unless match

      first, last = [match[1].to_i, (match[2] || match[1]).to_i].minmax
      first..last
    end
  end
end
