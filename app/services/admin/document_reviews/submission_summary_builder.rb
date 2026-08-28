# frozen_string_literal: true

module Admin
  module DocumentReviews
    class SubmissionSummaryBuilder < ApplicationService
      def initialize(submission:)
        @submission = submission
      end

      def call
        ReviewSummary.new(
          pending_review: pending_review_count,
          rejected: rejected_count,
          required_total: required_items.count,
          review_state: review_state,
          verified: verified_count
        )
      end

      private

      def pending_review_count
        required_items.count { |item| item.candidate_document.status_code == 'under_verification' }
      end

      def rejected_count
        required_items.count { |item| item.candidate_document.status_code == 'rejected' }
      end

      def required_items
        @required_items ||= @submission.submission_items.select(&:required)
      end

      def review_state
        ReviewStateResolver.call(
          pending_review: pending_review_count,
          rejected: rejected_count,
          required_total: required_items.count,
          verified: verified_count
        )
      end

      def verified_count
        required_items.count { |item| item.candidate_document.status_code == 'verified' }
      end
    end
  end
end
