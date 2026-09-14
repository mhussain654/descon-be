# frozen_string_literal: true

require 'date'

module Admin
  module Communications
    # Paginated, filterable listing over the central Communication log --
    # every channel (SMS, email, notification, AI voice call) in one place,
    # newest first by default. Mirrors Admin::AuditEvents::IndexQuery's shape.
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_SORTS = %w[created_at].freeze
      SIMPLE_FILTER_COLUMNS = {
        'channel' => 'channel_code', 'direction' => 'direction_code', 'status' => 'status_code'
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
        paginate(apply_sort(apply_filters(preloaded_scope)))
      end

      private

      # eager_load (not includes/joins) so the LEFT OUTER JOIN needed to
      # filter by candidate also hydrates candidate_assignment.candidate for
      # the serializer, avoiding an N+1 there.
      def preloaded_scope
        @scope.eager_load(candidate_assignment: :candidate).includes(:initiated_by)
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
        allowed = SIMPLE_FILTER_COLUMNS.keys + %w[candidate_assignment candidate occurred_from occurred_to]
        unsupported = values.keys - allowed
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_date_range!(values)
        values
      end

      def apply_filter(scope, name:, value:)
        return scope.where(SIMPLE_FILTER_COLUMNS.fetch(name) => value) if SIMPLE_FILTER_COLUMNS.key?(name)
        return scope.where(candidate_assignment_id: assignment_id_for(value)) if name == 'candidate_assignment'
        return scope.where(candidate_assignments: { candidate_id: candidate_id_for(value) }) if name == 'candidate'
        return apply_date_filter(scope, name:, value:) if name.start_with?('occurred_')

        scope
      end

      def apply_date_filter(scope, name:, value:)
        if name == 'occurred_from'
          return scope.where(created_at: date_for(value, field: 'filter.occurred_from').beginning_of_day..)
        end

        scope.where(created_at: ..date_for(value, field: 'filter.occurred_to').end_of_day)
      end

      def assignment_id_for(value)
        assignment = CandidateAssignment.find_by(public_id: value.to_s.strip)
        raise InvalidQueryParameterError.new(field: 'filter.candidate_assignment') if assignment.blank?

        assignment.id
      end

      def candidate_id_for(value)
        candidate = Candidate.find_by(public_id: value.to_s.strip)
        raise InvalidQueryParameterError.new(field: 'filter.candidate') if candidate.blank?

        candidate.id
      end

      def validate_date_range!(values)
        from = values['occurred_from'].presence && date_for(values['occurred_from'], field: 'filter.occurred_from')
        to = values['occurred_to'].presence && date_for(values['occurred_to'], field: 'filter.occurred_to')
        raise InvalidQueryParameterError.new(field: 'filter.occurred_to') if from && to && from > to
      end

      def date_for(value, field:)
        Date.iso8601(value.to_s)
      rescue Date::Error
        raise InvalidQueryParameterError.new(field:)
      end

      def apply_sort(scope)
        value = @params[:sort].to_s.strip
        return scope.order(created_at: :desc, id: :desc) if value.blank?

        direction = value.start_with?('-') ? :desc : :asc
        field = value.delete_prefix('-')
        raise UnsupportedSortError.new(sort_name: field) unless ALLOWED_SORTS.include?(field)

        scope.order(field => direction, id: :desc)
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
  end
end
