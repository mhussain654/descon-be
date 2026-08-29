# frozen_string_literal: true

module Candidates
  module BankDetails
    class RequestValidator < ApplicationService
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_DOCUMENT_MAX_BYTES', 5.megabytes).to_i

      def initialize(candidate:, attributes:)
        @candidate = candidate
        @attributes = attributes
      end

      def call
        raise NoCurrentAssignmentError if @candidate.current_assignment.blank?

        validate_account_fields!
        validate_proof!
      end

      private

      def validate_account_fields!
        raise MissingAccountTitleError if account_title.blank?
        raise MissingAccountNumberError if account_number.blank?
        raise InvalidAccountNumberError unless CandidateBankDetail::ACCOUNT_NUMBER_FORMAT.match?(account_number)
        raise MissingBankNameError if bank_name.blank?
      end

      def validate_proof!
        raise MissingBankProofError if proof.blank?
        raise EmptyFileError if proof.size.to_i.zero?
        raise FileTooLargeError if proof.size.to_i > MAX_FILE_BYTES
      end

      def account_title
        @account_title ||= @attributes.account_title.to_s.strip.squish
      end

      def account_number
        @account_number ||= AccountNumberNormalizer.call(account_number: @attributes.account_number)
      end

      def bank_name
        @bank_name ||= @attributes.bank_name.to_s.strip.squish
      end

      def proof
        @attributes.proof
      end
    end
  end
end
