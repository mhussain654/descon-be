# frozen_string_literal: true

module Admin
  module CandidateImports
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_STATUSES = CandidateImportBatch::STATUSES.freeze
      ALLOWED_SORTS = %w[created_at processed_at status].freeze

      attr_reader :pagination, :applied_filters

      def initialize(scope:, params:)
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
        return scope if values.empty?

        scope.where(status: values.fetch('status'))
      end

      def filter_values
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        values = raw.to_unsafe_h.compact_blank
        unsupported = values.keys - ['status']
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?
        raise InvalidQueryParameterError.new(field: 'filter.status') unless values['status'].blank? ||
                                                                      ALLOWED_STATUSES.include?(values['status'])

        values
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
