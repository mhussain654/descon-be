# frozen_string_literal: true

module Candidates
  module Documents
    # Checks one upload's files against its requirement before anything is
    # stored: file count, each file's detected type and size, and the side
    # labels -- every file needs an allowed label when the requirement uses
    # them (none otherwise), labels can't repeat (except `certificate`),
    # front/back and page_1/page_2 come as complete pairs, and `combined` is a
    # single PDF standing alone.
    #
    # `entries` are `{ details: UploadedFileDetails, side_code: String|nil }`.
    class FileSetValidator < ApplicationService
      PDF = 'application/pdf'

      def initialize(requirement:, entries:)
        @requirement = requirement
        @entries = entries
      end

      def call
        validate_count!
        @entries.each_with_index { |entry, index| validate_file!(entry, index) }
        validate_side_codes!
      end

      private

      def validate_count!
        count = @entries.size
        limits = { minimum_files: @requirement.minimum_files, maximum_files: @requirement.maximum_files }
        raise InvalidDocumentFilesError.new(reason: 'too_few_files', details: limits) if count < limits[:minimum_files]
        raise InvalidDocumentFilesError.new(reason: 'too_many_files', details: limits) if count > limits[:maximum_files]
      end

      def validate_file!(entry, index)
        field = "candidate_document.files[#{index}].file"
        details = entry.fetch(:details)
        raise EmptyFileError.new(field:) if details.byte_size.zero?
        raise FileTooLargeError.new(field:) if details.byte_size > @requirement.maximum_file_size
        return if @requirement.accepted_content_types.include?(details.content_type)

        raise UnsupportedFileTypeError.new(field:)
      end

      def validate_side_codes!
        side_codes = @entries.pluck(:side_code)
        return validate_unlabelled!(side_codes) if @requirement.allowed_side_codes.empty?

        side_codes.each_with_index { |side_code, index| validate_side_code!(side_code, index) }
        validate_no_duplicates!(side_codes)
        validate_combined!(side_codes)
        validate_pairs!(side_codes)
      end

      def validate_unlabelled!(side_codes)
        index = side_codes.index(&:present?)
        invalid!('side_code_not_allowed', index) if index
      end

      def validate_side_code!(side_code, index)
        invalid!('side_code_required', index) if side_code.blank?
        invalid!('side_code_not_allowed', index) unless @requirement.allowed_side_codes.include?(side_code)
      end

      def validate_no_duplicates!(side_codes)
        repeated = side_codes.tally.find do |side_code, count|
          count > 1 && CandidateDocumentFile::REPEATABLE_SIDE_CODES.exclude?(side_code)
        end
        return unless repeated

        raise InvalidDocumentFilesError.new(reason: 'duplicate_side_code',
                                            details: { side_code: repeated.first })
      end

      def validate_combined!(side_codes)
        index = side_codes.index('combined')
        return if index.nil?

        raise InvalidDocumentFilesError.new(reason: 'combined_must_be_alone') if side_codes.size > 1
        return if @requirement.combined_pdf_allowed && @entries[index][:details].content_type == PDF

        invalid!('combined_requires_pdf', index)
      end

      def validate_pairs!(side_codes)
        CandidateDocumentFile::SIDE_PAIRS.each do |pair|
          present = pair & side_codes
          next if present.empty? || present.size == pair.size

          raise InvalidDocumentFilesError.new(reason: 'incomplete_side_pair',
                                              details: { missing_side_code: (pair - present).first })
        end
      end

      def invalid!(reason, index)
        raise InvalidDocumentFilesError.new(reason:, field: "candidate_document.files[#{index}].side_code")
      end
    end
  end
end
