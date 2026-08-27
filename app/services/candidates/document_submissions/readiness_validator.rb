# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class ReadinessValidator < ApplicationService
      ALREADY_SUBMITTED_STATES = %w[submitted partially_verified verified].freeze

      def initialize(documents_to_submit:, progress:)
        @documents_to_submit = documents_to_submit
        @progress = progress
      end

      def call
        raise DocumentsIncompleteError.new(blocking_requirements:) if blocking_reason?('missing')
        raise DocumentsRejectedError.new(blocking_requirements:) if blocking_reason?('rejected')
        raise AlreadySubmittedError if already_submitted?
        raise SubmissionNotAllowedError unless @progress.documents.can_submit
      end

      private

      def already_submitted?
        @documents_to_submit.empty? && ALREADY_SUBMITTED_STATES.include?(@progress.documents.submission_state)
      end

      def blocking_reason?(reason)
        @progress.documents.blocking_requirements.any? { |requirement| requirement.reason == reason }
      end

      def blocking_requirements
        @progress.documents.blocking_requirements.map do |requirement|
          {
            requirement_code: requirement.requirement_code,
            name: requirement.name,
            reason: requirement.reason
          }
        end
      end
    end
  end
end
