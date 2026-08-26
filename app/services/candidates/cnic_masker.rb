# frozen_string_literal: true

module Candidates
  module CnicMasker
    def self.call(cnic)
      normalized_cnic = CnicNormalizer.call(cnic)
      return normalized_cnic unless normalized_cnic.match?(Candidate::CNIC_FORMAT)

      "#{normalized_cnic[0, 6]}*******-#{normalized_cnic[-1]}"
    end
  end
end
