# frozen_string_literal: true

module Candidates
  module Documents
    class PccIssueDateResolver < ApplicationService
      def initialize(requirement:, issued_on:)
        @requirement = requirement
        @issued_on = issued_on
      end

      def call
        return unless pcc_requirement?

        validate_presence!
        validate_future_date!(parsed_issued_on)
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
