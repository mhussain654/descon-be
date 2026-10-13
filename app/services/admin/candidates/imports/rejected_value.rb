# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      # The CSV cell a row error is about, so staff can see what to fix
      # without opening the file -- only that one column, never the row.
      # Identity numbers are masked (a complete CNIC, mobile or passport
      # number is never echoed back), including malformed ones, which are
      # usually a complete number with a typo. Row-level errors (field
      # `row`) and blank cells have no value.
      module RejectedValue
        CNIC_FIELDS = %w[cnic next_of_kin_cnic].freeze
        PHONE_FIELDS = %w[mobile_number next_of_kin_mobile_number].freeze
        MASKED_FIELDS = (CNIC_FIELDS + PHONE_FIELDS + %w[passport_number]).freeze
        FALLBACK_VISIBLE_LENGTH = 2
        PHONE_MINIMUM_MASKED_LENGTH = PhoneNumbers::Masker::VISIBLE_PREFIX_LENGTH +
                                      PhoneNumbers::Masker::VISIBLE_SUFFIX_LENGTH + 1

        module_function

        def call(field:, source_values:)
          return unless CsvFileParser::SUPPORTED_HEADERS.include?(field)

          value = source_values.to_h[field].to_s.squish
          return if value.empty?
          return value unless MASKED_FIELDS.include?(field)

          masked(field:, value:)
        end

        def masked(field:, value:)
          return ::Candidates::CnicMasker.call(value) if CNIC_FIELDS.include?(field) && well_formed_cnic?(value)
          return PhoneNumbers::Masker.call(value) if PHONE_FIELDS.include?(field) && maskable_phone?(value)

          fallback_mask(value)
        end

        def well_formed_cnic?(value) = ::Candidates::CnicNormalizer.call(value).match?(::Candidate::CNIC_FORMAT)

        def maskable_phone?(value) = value.length >= PHONE_MINIMUM_MASKED_LENGTH

        # Keeps a couple of characters at each end so staff can still tell
        # which value it is; anything too short to show safely is fully starred.
        def fallback_mask(value)
          visible = FALLBACK_VISIBLE_LENGTH
          return '*' * value.length if value.length <= visible * 3

          "#{value[0, visible]}#{'*' * (value.length - (visible * 2))}#{value[-visible, visible]}"
        end
      end
    end
  end
end
