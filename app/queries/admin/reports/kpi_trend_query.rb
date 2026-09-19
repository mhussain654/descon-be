# frozen_string_literal: true

module Admin
  module Reports
    # Daily counts for the 3 sparkline-eligible admin-dashboard KPI cards
    # (admin dashboard redesign) -- real event-based activity trends
    # (registrations/payments/mobilizations per day), not a literal
    # point-in-time backlog size over time (no daily-snapshot mechanism
    # exists for that, and building one is out of proportion to a
    # sparkline). "Pending review" has no entry here for the same reason --
    # there is no honest daily-event proxy for a review backlog.
    class KpiTrendQuery < ApplicationQuery
      WINDOW_DAYS = 14

      def initialize(scope: Candidate.all, reference_date: Date.current)
        super()
        @scope = scope
        @reference_date = reference_date
      end

      def call
        {
          active_candidates: daily_series(candidate_created_counts),
          paid_payments: daily_series(paid_payment_counts),
          mobilized: daily_series(mobilized_counts)
        }
      end

      private

      def window_start
        @reference_date - (WINDOW_DAYS - 1)
      end

      def daily_series(counts_by_date)
        (window_start..@reference_date).map { |date| { date: date.iso8601, count: counts_by_date.fetch(date, 0) } }
      end

      def candidate_created_counts
        as_date_keyed_counts(
          @scope.where(created_at: window_start.beginning_of_day..@reference_date.end_of_day)
                .group('DATE(created_at)').count
        )
      end

      def paid_payment_counts
        as_date_keyed_counts(
          Payment.where(candidate_assignment_id: assignment_ids, status_code: 'paid')
                 .where(paid_at: window_start.beginning_of_day..@reference_date.end_of_day)
                 .group('DATE(paid_at)').count
        )
      end

      def mobilized_counts
        CandidateFlightDetail.where(candidate_assignment_id: assignment_ids)
                             .where(mobilized_on: window_start..@reference_date)
                             .group(:mobilized_on).count
      end

      # Grouping by a raw SQL DATE(...) cast can return string keys
      # depending on how the adapter types the result; grouping by a native
      # date column (mobilized_counts above) already returns real Date keys.
      # Normalized here so daily_series's #fetch always matches.
      def as_date_keyed_counts(counts)
        counts.transform_keys { |key| key.is_a?(String) ? Date.parse(key) : key }
      end

      def assignment_ids
        @assignment_ids ||= CurrentAssignmentJoin.call(scope: @scope).select('current_assignments.id')
      end
    end
  end
end
