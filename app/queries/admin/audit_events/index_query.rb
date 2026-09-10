# frozen_string_literal: true

require 'date'

module Admin
  module AuditEvents
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_FILTERS = %w[actor action entity_type candidate occurred_from occurred_to].freeze
      ALLOWED_SORTS = %w[occurred_at].freeze
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

      def preloaded_scope
        @scope.includes(:actor, :candidate)
      end

      def apply_filters(scope)
        filters.reduce(scope) { |current, (name, value)| apply_filter(current, name:, value:) }
      end

      def filters
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        values = raw.to_unsafe_h.compact_blank
        unsupported = values.keys - ALLOWED_FILTERS
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_date_range!(values)
        @applied_filters = values
      end

      def apply_filter(scope, name:, value:)
        return scope.where(actor_id: actor_id_for(value)) if name == 'actor'
        return scope.where(action_code: code_list(value)) if name == 'action'
        return scope.where(entity_type: code_list(value)) if name == 'entity_type'
        return scope.where(candidate_id: candidate_id_for(value)) if name == 'candidate'
        return apply_date_filter(scope, name:, value:) if name.start_with?('occurred_')

        scope
      end

      def apply_date_filter(scope, name:, value:)
        if name == 'occurred_from'
          return scope.where(occurred_at: date_for(value,
                                                   field: 'filter.occurred_from').beginning_of_day..)
        end

        scope.where(occurred_at: ..date_for(value, field: 'filter.occurred_to').end_of_day)
      end

      def code_list(value)
        list = value.to_s.split(',').map(&:strip).compact_blank
        raise InvalidQueryParameterError.new(field: 'filter.action') if list.empty?

        list
      end

      def actor_id_for(value)
        actor = User.find_by(public_id: value.to_s.strip)
        raise InvalidQueryParameterError.new(field: 'filter.actor') if actor.blank?

        actor.id
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
        return scope.order(occurred_at: :desc, id: :desc) if value.blank?

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
