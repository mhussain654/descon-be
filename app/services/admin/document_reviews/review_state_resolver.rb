# frozen_string_literal: true

module Admin
  module DocumentReviews
    class ReviewStateResolver < ApplicationService
      def initialize(pending_review:, rejected:, required_total:, verified:)
        @pending_review = pending_review
        @rejected = rejected
        @required_total = required_total
        @verified = verified
      end

      def call
        return 'changes_required' if @rejected.positive?
        return 'verified' if verified?
        return 'partially_reviewed' if partially_reviewed?
        return 'pending_review' if @pending_review.positive?

        'pending_review'
      end

      private

      def partially_reviewed?
        @pending_review.positive? && @verified.positive?
      end

      def verified?
        @required_total.positive? && @verified == @required_total
      end
    end
  end
end
