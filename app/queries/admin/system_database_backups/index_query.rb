# frozen_string_literal: true

module Admin
  module SystemDatabaseBackups
    # Paginated, most-recent-first list of database backup attempts (MPS-903).
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      attr_reader :pagination

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @pagination = {}
      end

      def call
        paginate(@scope.order(taken_at: :desc, id: :desc))
      end

      # Zero-filled counts per backup status -- no filters on this query to
      # exclude (unlike DocumentReviewQueueQuery#summary), so this simply
      # groups the whole scope.
      def summary
        counts = @scope.group(:status_code).count
        SystemDatabaseBackup::STATUS_CODES.map { |code| { code:, count: counts.fetch(code, 0) } }
      end

      private

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
