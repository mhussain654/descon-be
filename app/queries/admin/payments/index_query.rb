# frozen_string_literal: true

require 'date'

module Admin
  module Payments
    # rubocop:disable Metrics/ClassLength
    class IndexQuery < ApplicationQuery
      # A search that is a number also matches the registration number.
      SEARCH_SQL = <<~SQL.squish
        candidates.full_name ILIKE :match OR candidate_assignments.registration_number = :number OR
        payments.external_reference ILIKE :match OR payments.voucher_number ILIKE :match OR
        payments.kuickpay_reference_number ILIKE :match
      SQL

      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_STATUSES = Payment::STATUS_CODES.freeze
      ALLOWED_SORTS = %w[created_at paid_at amount status_code].freeze
      ALLOWED_RECONCILIATION_STATES = %w[open resolved clean].freeze
      PAID_DATE_FILTERS = %w[paid_from paid_to].freeze
      # Fees are paid in Pakistan, so a paid day is a calendar day there, not UTC.
      PAID_DATE_TIME_ZONE = 'Asia/Karachi'
      SIMPLE_FILTER_COLUMNS = {
        'status' => 'status_code', 'provider_code' => 'provider_code',
        'payment_type_code' => 'payment_type_code', 'currency_code' => 'currency_code'
      }.freeze

      attr_reader :pagination, :applied_filters

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @pagination = {}
        @applied_filters = {}
      end

      def call
        paginate(apply_sort(apply_filters(apply_search(preloaded_scope))))
      end

      # Zero-filled counts per payment status, scoped by every active filter
      # except `status` -- same convention as DocumentReviewQueueQuery#summary.
      # Deliberately its own query, not a reuse of Admin::Reports::
      # PaymentSummaryQuery: that one is candidate-rooted (current-assignment
      # -only) and doesn't understand this list's own filters
      # (provider_code/payment_type_code/currency_code/reconciliation_state/
      # search/date range) or its broader scope (every payment on an
      # assignment, not just the current one).
      def summary
        counts = scope_without_status.group(:status_code).count
        Payment::STATUS_CODES.map { |code| { code:, count: counts.fetch(code, 0) } }
      end

      # How many candidates paid, and how much, under every active filter: with
      # `paid_from`/`paid_to` set to today it answers "who paid today".
      def paid_total
        paid = apply_filters(apply_search(@scope.left_joins(candidate_assignment: :candidate)))
               .where(status_code: 'paid').reorder(nil)
        {
          candidate_count: paid.distinct.count('candidate_assignments.candidate_id'),
          payment_count: paid.count,
          amounts: paid.group(:currency_code).sum(:amount).sort.map do |currency_code, amount|
            { currency_code:, amount: format('%.2f', amount) }
          end
        }
      end

      private

      def scope_without_status
        filter_values.except('status').reduce(apply_search(preloaded_scope)) do |s, (name, value)|
          apply_filter(s, name:, value:)
        end
      end

      def preloaded_scope
        # eager_load (not joins) so the same LEFT OUTER JOIN this query
        # already needs for filtering/searching/sorting on
        # candidate_assignments/candidates columns also hydrates those
        # associations -- the serializer reads payment.candidate_assignment
        # .candidate for every row, and a plain `joins` would leave that an
        # N+1 (one extra query per row).
        @scope.eager_load(candidate_assignment: :candidate)
      end

      def apply_search(scope)
        value = @params[:search].to_s.strip
        return scope if value.blank?

        scope.where(SEARCH_SQL, match: "%#{ActiveRecord::Base.sanitize_sql_like(value)}%",
                                number: ::Candidates::RegistrationNumberParser.search_number(value))
      end

      def apply_filters(scope)
        values = filter_values
        @applied_filters = values
        values.reduce(scope) { |filtered, (name, value)| apply_filter(filtered, name:, value:) }
      end

      def filter_values
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        values = raw.to_unsafe_h.compact_blank
        unsupported = values.keys - (%w[status provider_code payment_type_code currency_code created_from created_to
                                        reconciliation_state country_code] + PAID_DATE_FILTERS +
                                       RegisteredDateFilter::NAMES)
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_filter_values!(values)
        values
      end

      def validate_filter_values!(values)
        validate_inclusion!(values['status'], ALLOWED_STATUSES, 'filter.status')
        validate_inclusion!(values['reconciliation_state'], ALLOWED_RECONCILIATION_STATES,
                            'filter.reconciliation_state')
        validate_date_range!(values)
        validate_paid_date_range!(values)
        RegisteredDateFilter.validate!(values)
      end

      def validate_inclusion!(value, allowed, field)
        return if value.blank? || allowed.include?(value)

        raise InvalidQueryParameterError.new(field:)
      end

      def validate_date_range!(values)
        from = values['created_from'].presence && date_for(values['created_from'], field: 'filter.created_from')
        to = values['created_to'].presence && date_for(values['created_to'], field: 'filter.created_to')
        raise InvalidQueryParameterError.new(field: 'filter.created_to') if from && to && from > to
      end

      def validate_paid_date_range!(values)
        from = values['paid_from'].presence && date_for(values['paid_from'], field: 'filter.paid_from')
        to = values['paid_to'].presence && date_for(values['paid_to'], field: 'filter.paid_to')
        raise InvalidQueryParameterError.new(field: 'filter.paid_to') if from && to && from > to
      end

      def apply_filter(scope, name:, value:)
        return scope.where(SIMPLE_FILTER_COLUMNS.fetch(name) => value) if SIMPLE_FILTER_COLUMNS.key?(name)
        return scope.where(paid_at: paid_range(name, value)) if PAID_DATE_FILTERS.include?(name)

        apply_other_filter(scope, name:, value:)
      end

      def apply_other_filter(scope, name:, value:)
        if name == 'created_from'
          return scope.where(created_at: date_for(value,
                                                  field: 'filter.created_from').beginning_of_day..)
        end
        return scope.where(created_at: ..date_for(value, field: 'filter.created_to').end_of_day) if name == 'created_to'
        return apply_reconciliation_state_filter(scope, value) if name == 'reconciliation_state'
        return scope.where(candidate_assignment_id: candidate_assignments_for(name, value)) if candidate_filter?(name)

        scope
      end

      # The candidate's country and registered (added or imported) day, so a
      # batch's payments can be seen together.
      def candidate_filter?(name) = name == 'country_code' || RegisteredDateFilter::NAMES.include?(name)

      def candidate_assignments_for(name, value)
        return CandidateAssignment.where(country_id: country_id(value)).select(:id) if name == 'country_code'

        CandidateAssignment.where(candidate_id: ::Candidate.where(created_at: RegisteredDateFilter.range(name, value))
                                                           .select(:id)).select(:id)
      end

      def country_id(code)
        country = Country.find_by(code: code.to_s.strip.downcase)
        raise InvalidQueryParameterError.new(field: 'filter.country_code') if country.blank?

        country.id
      end

      def apply_reconciliation_state_filter(scope, value)
        open_ids = PaymentReconciliationFinding.open_state.select(:payment_id)
        all_ids = PaymentReconciliationFinding.select(:payment_id)
        case value
        when 'open' then scope.where(id: open_ids)
        when 'resolved' then scope.where(id: all_ids).where.not(id: open_ids)
        when 'clean' then scope.where.not(id: all_ids)
        else scope
        end
      end

      def paid_range(name, value)
        day = date_for(value, field: "filter.#{name}")
        start = Time.find_zone!(PAID_DATE_TIME_ZONE).local(day.year, day.month, day.day)
        name == 'paid_from' ? (start..) : (..start.end_of_day)
      end

      def date_for(value, field:)
        Date.iso8601(value)
      rescue Date::Error
        raise InvalidQueryParameterError.new(field:)
      end

      def apply_sort(scope)
        value = @params[:sort].to_s.strip
        return scope.order(created_at: :desc, public_id: :asc) if value.blank?

        direction = value.start_with?('-') ? :desc : :asc
        field = value.delete_prefix('-')
        raise UnsupportedSortError.new(sort_name: field) unless ALLOWED_SORTS.include?(field)

        scope.order(field => direction, public_id: :asc)
      end

      def paginate(scope)
        number = positive_integer(@params.dig(:page, :number), 'page.number', default: 1)
        size = positive_integer(@params.dig(:page, :size), 'page.size', default: DEFAULT_PAGE_SIZE)
        raise InvalidQueryParameterError.new(field: 'page.size') if size > MAX_PAGE_SIZE

        total_count = scope.count
        @pagination = { page: number, per_page: size, total_count:, total_pages: (total_count.to_f / size).ceil }
        scope.offset((number - 1) * size).limit(size)
      end

      def positive_integer(value, field, default:)
        return default if value.blank?

        number = Integer(value, exception: false)
        raise InvalidQueryParameterError.new(field:) unless number&.positive?

        number
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
