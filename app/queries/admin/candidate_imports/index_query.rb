# frozen_string_literal: true

require 'date'

module Admin
  module CandidateImports
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_STATUSES = CandidateImportBatch::STATUSES.freeze
      ALLOWED_SORTS = %w[created_at processed_at status].freeze

      attr_reader :pagination, :applied_filters

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @pagination = {}
        @applied_filters = {}
      end

      def call
        paginate(apply_sort(apply_filters(@scope)))
      end

      private

      def apply_filters(scope)
        values = filter_values
        @applied_filters = values
        values.reduce(scope) { |filtered, (name, value)| apply_filter(filtered, name:, value:) }
      end

      def filter_values
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        values = raw.to_unsafe_h.compact_blank
        unsupported = values.keys - %w[status actor_id created_from created_to template_version]
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_filter_values!(values)
        values
      end

      def validate_filter_values!(values)
        validate_status!(values['status'])
        validate_actor!(values['actor_id'])
        validate_template_version!(values['template_version'])
        validate_date_range!(values)
      end

      def apply_filter(scope, name:, value:)
        case name
        when 'status' then scope.where(status: value)
        when 'actor_id' then scope.where(actor: User.find_by!(public_id: value))
        when 'template_version' then scope.where(template_version: value)
        when 'created_from' then from_date_scope(scope, value)
        when 'created_to' then scope.where(created_at: ..date_for(value, field: 'filter.created_to').end_of_day)
        end
      rescue ActiveRecord::RecordNotFound
        raise InvalidQueryParameterError.new(field: 'filter.actor_id')
      end

      def validate_status!(value)
        return if value.blank? || ALLOWED_STATUSES.include?(value)

        raise InvalidQueryParameterError.new(field: 'filter.status')
      end

      def validate_actor!(value)
        return if value.blank? || value.match?(/\A[0-9a-f]{8}-[0-9a-f-]{27}\z/i)

        raise InvalidQueryParameterError.new(field: 'filter.actor_id')
      end

      def validate_template_version!(value)
        return if value.blank? || value.match?(/\Av[1-9][0-9]*\z/)

        raise InvalidQueryParameterError.new(field: 'filter.template_version')
      end

      def validate_date_range!(values)
        from = values['created_from'].presence && date_for(values['created_from'], field: 'filter.created_from')
        to = values['created_to'].presence && date_for(values['created_to'], field: 'filter.created_to')
        raise InvalidQueryParameterError.new(field: 'filter.created_to') if from && to && from > to
      end

      def date_for(value, field:)
        Date.iso8601(value)
      rescue Date::Error
        raise InvalidQueryParameterError.new(field:)
      end

      def from_date_scope(scope, value)
        scope.where(created_at: date_for(value, field: 'filter.created_from').beginning_of_day..)
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
  end
end
