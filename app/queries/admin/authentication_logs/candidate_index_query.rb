# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # The Authentication page's Candidates tab: one row per candidate with how
    # many sign-in codes (OTPs) were sent, how many times they signed in, and
    # when they last signed in and last used the app. Counts come from
    # candidate_otp_challenges (one row per code sent) and candidate_sessions
    # (one row per successful sign-in), aggregated once per page in SQL.
    #
    # Sort with `sort` (prefix `-` for newest/largest first); the default is
    # the most recent sign-in first, candidates who never signed in last.
    # `filter[activity]` is `signed_in` or `never_signed_in`.
    class CandidateIndexQuery < ApplicationQuery
      SORT_COLUMNS = Sort.columns(
        'last_login_at' => 'session_stats.last_login_at',
        'last_seen_at' => 'session_stats.last_seen_at',
        'login_count' => 'login_count',
        'otp_count' => 'otp_count',
        'full_name' => 'candidates.full_name'
      )
      ACTIVITIES = %w[signed_in never_signed_in].freeze
      ALLOWED_FILTERS = %w[activity].freeze

      attr_reader :applied_filters

      delegate :pagination, to: :@page

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @page = Page.new(params[:page])
        @applied_filters = {}
      end

      def call
        listed = apply_filters(apply_search(joined_scope))
        sorted = Sort.apply(listed.select(select_sql), @params[:sort], columns: SORT_COLUMNS)
        @page.apply(sorted, total_count: listed.count).to_a
      end

      private

      def joined_scope
        @scope
          .joins(latest_assignment_join)
          .joins(stats_join(otp_stats, 'otp_stats'))
          .joins(stats_join(session_stats, 'session_stats'))
      end

      def select_sql
        <<~SQL.squish
          candidates.id, candidates.public_id, candidates.full_name, candidates.cnic, candidates.active,
          current_assignments.registration_number AS registration_number,
          COALESCE(otp_stats.otp_count, 0) AS otp_count, otp_stats.last_otp_at,
          COALESCE(session_stats.login_count, 0) AS login_count,
          session_stats.last_login_at, session_stats.last_seen_at
        SQL
      end

      def latest_assignment_join
        <<~SQL.squish
          LEFT JOIN candidate_assignments current_assignments ON current_assignments.id = (
            SELECT assignments.id FROM candidate_assignments assignments
            WHERE assignments.candidate_id = candidates.id
            ORDER BY assignments.created_at DESC, assignments.id DESC LIMIT 1
          )
        SQL
      end

      def stats_join(relation, alias_name)
        AggregateJoin.call(table: Candidate.arel_table, relation:, alias_name:, foreign_key: :candidate_id)
      end

      def otp_stats
        CandidateOtpChallenge.where.not(candidate_id: nil).group(:candidate_id)
                             .select('candidate_id, COUNT(*) AS otp_count, MAX(created_at) AS last_otp_at')
      end

      # A new session has no last_seen_at until the app's first request more
      # than five minutes later, so its sign-in time counts as app use too.
      def session_stats
        CandidateSession.group(:candidate_id).select(<<~SQL.squish)
          candidate_id, COUNT(*) AS login_count, MAX(created_at) AS last_login_at,
          MAX(COALESCE(last_seen_at, created_at)) AS last_seen_at
        SQL
      end

      # Name (partial), registration number, or CNIC. CNIC is encrypted
      # deterministically, so it is matched through ActiveRecord's hash
      # condition, never raw SQL.
      def apply_search(scope)
        value = @params[:search].to_s.strip
        return scope if value.blank?

        name = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
        number = ::Candidates::RegistrationNumberParser.search_number(value)
        scope.where('candidates.full_name ILIKE :name OR current_assignments.registration_number = :number',
                    name:, number:)
             .or(scope.where(cnic: ::Candidates::CnicNormalizer.call(value)))
      end

      def apply_filters(scope)
        filters = raw_filters
        activity = filters['activity']
        return scope if activity.blank?

        raise InvalidQueryParameterError.new(field: 'filter.activity') unless ACTIVITIES.include?(activity)

        @applied_filters = { activity: }
        never_signed_in = { session_stats: { candidate_id: nil } }
        activity == 'signed_in' ? scope.where.not(never_signed_in) : scope.where(never_signed_in)
      end

      def raw_filters
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.compact_blank.tap do |values|
          invalid = values.keys - ALLOWED_FILTERS
          raise UnsupportedFilterError.new(filter_name: invalid.first) if invalid.any?
        end
      end
    end
  end
end
