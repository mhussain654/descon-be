# frozen_string_literal: true

module Admin
  module AiCalls
    # Paginated listing over every CandidateAiCall (inbound, admin-triggered
    # outbound, and workflow-stage-triggered outbound), newest first.
    # Defaults to the manual-review queue (`filter[awaiting_review]=true`
    # is the implicit default) since that's this endpoint's primary use --
    # pass `filter[awaiting_review]=false` to browse all calls instead.
    # Mirrors Admin::Communications::IndexQuery's shape.
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100

      attr_reader :pagination, :applied_filters

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @pagination = {}
        @applied_filters = {}
      end

      def call
        paginate(apply_filters(preloaded_scope))
      end

      private

      def preloaded_scope
        @scope.includes(:candidate, :triggered_by, :reviewed_by).order(created_at: :desc, id: :desc)
      end

      def apply_filters(scope)
        @applied_filters = { 'awaiting_review' => awaiting_review? }
        awaiting_review? ? scope.awaiting_review : scope
      end

      def awaiting_review?
        raw = @params.dig(:filter, :awaiting_review)
        return true if raw.blank?

        ActiveModel::Type::Boolean.new.cast(raw)
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
