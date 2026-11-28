# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # The Authentication page's Staff tab: one row per staff account with how
    # many times it signed in, when it last signed in and was last active, and
    # how many wrong passwords were entered since its last successful sign-in
    # (Devise lockable's `failed_attempts`, cleared by a sign-in or when a
    # lock ends).
    #
    # A wrong password for an email that matches no account is logged with only
    # the masked email (Authentication::LoginService), so it can't be counted
    # against a person here.
    #
    # Sort with `sort` (prefix `-` for newest/largest first); the default is
    # the most recent sign-in first, accounts that never signed in last.
    class StaffIndexQuery < ApplicationQuery
      SORT_COLUMNS = Sort.columns(
        'last_login_at' => 'session_stats.last_login_at',
        'last_seen_at' => 'session_stats.last_seen_at',
        'login_count' => 'login_count',
        'email' => 'users.email'
      )

      delegate :pagination, to: :@page

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @page = Page.new(params[:page])
      end

      def call
        listed = apply_search(joined_scope)
        sorted = Sort.apply(listed.select(select_sql), @params[:sort], columns: SORT_COLUMNS)
        @page.apply(sorted, total_count: listed.count).to_a
      end

      private

      def joined_scope
        @scope.joins(
          AggregateJoin.call(table: User.arel_table, relation: session_stats, alias_name: 'session_stats',
                             foreign_key: :user_id)
        )
      end

      def select_sql
        <<~SQL.squish
          users.id, users.public_id, users.email, users.role, users.staff_state, users.failed_attempts,
          users.locked_at, COALESCE(session_stats.login_count, 0) AS login_count,
          session_stats.last_login_at, session_stats.last_seen_at
        SQL
      end

      # Every staff sign-in creates one session row, so sessions count logins.
      # A new session has no last_seen_at until a request more than five
      # minutes later, so its sign-in time counts as activity too.
      def session_stats
        Session.group(:user_id).select(<<~SQL.squish)
          user_id, COUNT(*) AS login_count, MAX(created_at) AS last_login_at,
          MAX(COALESCE(last_seen_at, created_at)) AS last_seen_at
        SQL
      end

      def apply_search(scope)
        value = @params[:search].to_s.strip
        return scope if value.blank?

        scope.where('users.email ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(value)}%")
      end
    end
  end
end
