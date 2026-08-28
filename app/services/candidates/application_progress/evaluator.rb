# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    class Evaluator < ApplicationService
      PROVIDED_STATUS_CODES = %w[pending_review uploaded verified].freeze
      SUBMISSION_ALLOWED_STATUS_CODES = %w[pending_review uploaded verified].freeze

      def initialize(candidate:, assignment:, current_documents_by_type:, requirements:)
        @assignment = assignment
        @candidate = candidate
        @current_documents_by_type = current_documents_by_type
        @requirements = requirements
      end

      def call
        Summary.new(
          candidate_status: @candidate.status_code,
          current_workflow_stage: @assignment&.current_workflow_stage,
          documents: documents_summary
        )
      end

      private

      def documents_summary
        DocumentsSummary.new(
          **document_counts,
          blocking_requirements:,
          can_submit:,
          completion_percentage:,
          submission_state:
        )
      end

      def blocking_requirements
        @blocking_requirements ||= required_requirements.filter_map do |requirement|
          blocking_requirement_for(requirement)
        end
      end

      def can_submit
        return false if @assignment.blank? || required_requirements.empty?
        return false if blocking_requirements.present?
        return false unless allowed_for_submission?

        required_documents.any? { |document| document&.api_status == 'uploaded' }
      end

      def completion_percentage
        return 0 if required_requirements.empty?

        (submitted_total * 100) / required_requirements.count
      end

      def missing = required_requirements.count { |requirement| document_for(requirement).blank? }

      def required_documents
        @required_documents ||= required_requirements.map { |requirement| document_for(requirement) }
      end

      def required_requirements = @required_requirements ||= @requirements.select(&:required)

      def submitted_total = required_documents.count { |document| valid_submission_evidence?(document) }

      def allowed_for_submission? = required_documents.all? { |document| allowed_submission_document?(document) }

      def count_status(status) = required_documents.count { |document| document&.api_status == status }

      def rejected = count_status('rejected')

      def document_counts
        {
          missing:,
          pending_review: count_status('pending_review'),
          rejected:,
          required_total: required_requirements.count,
          submitted_total:,
          uploaded: count_status('uploaded'),
          verified: count_status('verified')
        }
      end

      def blocking_requirement_for(requirement)
        document = document_for(requirement)
        return build_blocking_requirement(requirement, reason: 'missing') if document.blank?
        return build_blocking_requirement(requirement, reason: 'rejected') if document.api_status == 'rejected'
        return unless expired_pcc_requirement?(requirement:, document:)

        build_blocking_requirement(requirement, reason: 'expired')
      end

      def build_blocking_requirement(requirement, reason:)
        BlockingRequirement.new(
          requirement_code: requirement.document_type.code,
          name: requirement.document_type.name_for,
          reason:
        )
      end

      def document_for(requirement) = @current_documents_by_type[requirement.document_type_id]

      def allowed_submission_document?(document)
        SUBMISSION_ALLOWED_STATUS_CODES.include?(document&.api_status) && compliant_submission_evidence?(document)
      end

      def compliant_submission_evidence?(document)
        return false if document.blank?
        return true unless document.police_character?

        document.compliance_status != 'expired'
      end

      def valid_submission_evidence?(document)
        PROVIDED_STATUS_CODES.include?(document&.api_status) && compliant_submission_evidence?(document)
      end

      def expired_pcc_requirement?(requirement:, document:)
        requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE &&
          document.compliance_status == 'expired'
      end

      def submission_state
        StateResolver.call(
          assignment: @assignment,
          blocking_requirements:,
          can_submit:,
          required_documents:,
          required_requirements:
        )
      end
    end
  end
end
