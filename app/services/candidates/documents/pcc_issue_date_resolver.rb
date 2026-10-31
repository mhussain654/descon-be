# frozen_string_literal: true

module Candidates
  module Documents
    # Validates the PCC issue date given with an upload: present, a real date,
    # not in the future, and -- client rule -- issued no more than 5 months
    # ago, so the certificate (valid for 6 months) still has time left when
    # the visa is processed.
    class PccIssueDateResolver < ApplicationService
      MAXIMUM_AGE_MONTHS = 5

      def initialize(requirement:, issued_on:)
        @requirement = requirement
        @issued_on = issued_on
      end

      def call
        return unless pcc_requirement?

        validate_presence!
        validate_future_date!(parsed_issued_on)
        validate_not_too_old!(parsed_issued_on)
        parsed_issued_on
      end

      private

      def parsed_issued_on
        @parsed_issued_on ||= Date.iso8601(@issued_on.to_s)
      rescue ArgumentError
        raise ValidationError.new(
          field: 'candidate_document.issued_on',
          message: I18n.t('api.errors.pcc_issue_date_invalid')
        )
      end

      def pcc_requirement?
        @requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE
      end

      def validate_future_date!(issued_on)
        return unless issued_on.future?

        raise ValidationError.new(
          field: 'candidate_document.issued_on',
          message: I18n.t('api.errors.pcc_issue_date_in_future')
        )
      end

      def validate_not_too_old!(issued_on)
        return if issued_on >= MAXIMUM_AGE_MONTHS.months.ago.to_date

        raise ValidationError.new(
          field: 'candidate_document.issued_on',
          message: I18n.t('api.errors.pcc_issue_date_too_old', months: MAXIMUM_AGE_MONTHS)
        )
      end

      def validate_presence!
        return if @issued_on.present?

        raise ValidationError.new(
          field: 'candidate_document.issued_on',
          message: I18n.t('api.errors.pcc_issue_date_required')
        )
      end
    end
  end
end
