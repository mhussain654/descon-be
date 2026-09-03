# frozen_string_literal: true

require 'date'

module Admin
  module Payments
    # rubocop:disable Metrics/ClassLength
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_STATUSES = Payment::STATUS_CODES.freeze
      ALLOWED_SORTS = %w[created_at paid_at amount status_code].freeze
      ALLOWED_RECONCILIATION_STATES = %w[open resolved clean].freeze
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

      private

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

        match = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
        scope.where(
          <<~SQL.squish,
            candidates.full_name ILIKE :match OR candidate_assignments.reference_number ILIKE :match OR
            payments.external_reference ILIKE :match
          SQL
          match:
        )
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
        unsupported = values.keys - %w[status provider_code payment_type_code currency_code created_from created_to
                                       reconciliation_state]
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_filter_values!(values)
        values
      end

      def validate_filter_values!(values)
        validate_inclusion!(values['status'], ALLOWED_STATUSES, 'filter.status')
        validate_inclusion!(values['reconciliation_state'], ALLOWED_RECONCILIATION_STATES,
                            'filter.reconciliation_state')
        validate_date_range!(values)
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

      def apply_filter(scope, name:, value:)
        return scope.where(SIMPLE_FILTER_COLUMNS.fetch(name) => value) if SIMPLE_FILTER_COLUMNS.key?(name)
        if name == 'created_from'
          return scope.where(created_at: date_for(value,
                                                  field: 'filter.created_from').beginning_of_day..)
        end
        return scope.where(created_at: ..date_for(value, field: 'filter.created_to').end_of_day) if name == 'created_to'
        return apply_reconciliation_state_filter(scope, value) if name == 'reconciliation_state'

        scope
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
