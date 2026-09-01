# frozen_string_literal: true

require 'csv'

module Admin
  module Candidates
    module Imports
      class Template < ApplicationService
        VERSION = 'v1'
        OPTIONAL_HEADERS = %w[
          passport_number
          next_of_kin_name
          next_of_kin_relationship
          next_of_kin_mobile_number
          next_of_kin_cnic
        ].freeze

        def call
          CSV.generate(encoding: Encoding::UTF_8) do |csv|
            csv << headers
            csv << example_row
          end
        end

        def self.headers = CsvFileParser::REQUIRED_HEADERS + OPTIONAL_HEADERS
        def self.filename = "candidate-import-template-#{VERSION}.csv"

        private

        def headers = self.class.headers

        def example_row
          [
            'Example Candidate', '42101-1234567-1', '+923001234567', 'DES-EXAMPLE-001', 'en', 'registered',
            'registered', 'qatar', 'qatar_infrastructure', 'electrician', 'true', 'AB123456', 'مثالی سرپرست',
            'sibling', '+923001234568', '42101-1234567-2'
          ]
        end
      end
    end
  end
end
