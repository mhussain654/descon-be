# frozen_string_literal: true

require 'csv'

module Admin
  module Candidates
    module Imports
      class Template < ApplicationService
        VERSION = 'v1'

        def call
          CSV.generate(encoding: Encoding::UTF_8) do |csv|
            csv << headers
            csv << example_row
          end
        end

        # Every supported column except preferred_locale, which older files may
        # still carry: candidates pick their language in the app instead.
        LEFT_OUT_HEADERS = %w[preferred_locale].freeze

        def self.headers = CsvFileParser::SUPPORTED_HEADERS - LEFT_OUT_HEADERS
        def self.filename = "candidate-import-template-#{VERSION}.csv"

        private

        def headers = self.class.headers

        def example_row
          [
            'Example Candidate', '42101-1234567-1', '+923001234567', 'registered', 'registered', 'Qatar',
            'Qatar Infrastructure', 'Electrician', 'true', '500001', 'AB123456', 'مثالی سرپرست',
            'sibling', '+923001234568', '42101-1234567-2', 'candidate@example.com', VERSION
          ]
        end
      end
    end
  end
end
