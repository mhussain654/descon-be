# frozen_string_literal: true

module Admin
  class DocumentReviewQueueParams
    DEFAULT_PAGE_NUMBER = 1
    DEFAULT_PAGE_SIZE = 20
    DEFAULT_STATUSES = %w[pending_review partially_reviewed].freeze
    MAX_PAGE_SIZE = 100
    REVIEW_STATES = %w[pending_review partially_reviewed changes_required verified].freeze

    def initialize(params:)
      @params = params
    end

    def candidate_public_id = filter_value(:candidate_public_id)

    def country_code = filter_value(:country_code)

    def page_number
      positive_integer(@params.dig(:page, :number), default: DEFAULT_PAGE_NUMBER, field: 'page.number')
    end

    def page_size
      size = positive_integer(@params.dig(:page, :size), default: DEFAULT_PAGE_SIZE, field: 'page.size')
      raise InvalidQueryParameterError.new(field: 'page.size') if size > MAX_PAGE_SIZE

      size
    end

    def project_code = filter_value(:project_code)

    def statuses
      values = filter_value(:status).to_s.split(',').map(&:strip).compact_blank
      values = DEFAULT_STATUSES if values.empty?
      raise InvalidQueryParameterError.new(field: 'filter.status') unless (values - REVIEW_STATES).empty?

      values
    end

    def submitted_from = parse_time(filter_value(:submitted_from), field: 'filter.submitted_from')

    def submitted_to = parse_time(filter_value(:submitted_to), field: 'filter.submitted_to')

    private

    def filters
      raw_filters = @params[:filter]
      return {} unless raw_filters.respond_to?(:to_unsafe_h)

      raw_filters.to_unsafe_h.compact_blank
    end

    def filter_value(name)
      filters[name.to_s]
    end

    def parse_time(value, field:)
      return if value.blank?

      Time.iso8601(value).in_time_zone
    rescue ArgumentError
      raise InvalidQueryParameterError.new(field:)
    end

    def positive_integer(value, default:, field:)
      return default if value.blank?

      integer = Integer(value, exception: false)
      raise InvalidQueryParameterError.new(field:) unless integer&.positive?

      integer
    end
  end
end
