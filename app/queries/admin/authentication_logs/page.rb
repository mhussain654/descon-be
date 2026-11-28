# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # `page[number]` / `page[size]` handling shared by the Authentication
    # page's candidate and staff lists: 25 rows by default, at most 100.
    class Page
      DEFAULT_SIZE = 25
      MAX_SIZE = 100

      attr_reader :pagination

      def initialize(params)
        @number = positive_integer(params&.dig(:number), 'page.number', default: 1)
        @size = positive_integer(params&.dig(:size), 'page.size', default: DEFAULT_SIZE)
        raise InvalidQueryParameterError.new(field: 'page.size') if @size > MAX_SIZE

        @pagination = {}
      end

      # `total_count` is counted separately because the listed relation
      # carries a custom SELECT with aggregates.
      def apply(scope, total_count:)
        @pagination = { page: @number, per_page: @size, total_count:, total_pages: (total_count.to_f / @size).ceil }
        scope.offset((@number - 1) * @size).limit(@size)
      end

      private

      def positive_integer(value, field, default:)
        return default if value.blank?

        number = Integer(value.to_s, exception: false)
        raise InvalidQueryParameterError.new(field:) unless number&.positive?

        number
      end
    end
  end
end
