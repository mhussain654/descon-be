# frozen_string_literal: true

module Users
  class IndexQuery < ApplicationQuery
    DEFAULT_PAGE_NUMBER = 1
    DEFAULT_PAGE_SIZE = 20
    MAX_PAGE_SIZE = 100
    ALLOWED_FILTERS = %w[active email role].freeze
    BOOLEAN_FILTER_VALUES = { 'true' => true, 'false' => false }.freeze
    ALLOWED_SORTS = {
      'created_at' => :created_at,
      'email' => :email,
      'public_id' => :public_id,
      'role' => :role
    }.freeze

    attr_reader :pagination

    def initialize(scope:, params:)
      super()
      @scope = scope
      @params = params
      @pagination = {}
    end

    def call
      filtered_scope = apply_filters(@scope)
      sorted_scope = apply_sort(filtered_scope)
      paginate(sorted_scope)
    end

    private

    def apply_filters(scope)
      filters.reduce(scope) do |current_scope, (filter_name, filter_value)|
        raise UnsupportedFilterError.new(filter_name:) unless ALLOWED_FILTERS.include?(filter_name)

        filter_scope(current_scope, filter_name, filter_value)
      end
    end

    def filter_scope(scope, filter_name, filter_value)
      case filter_name
      when 'active'
        scope.where(active: boolean_filter_value(filter_value))
      when 'email'
        email_scope(scope, filter_value)
      when 'role'
        role_scope(scope, filter_value)
      else
        scope.none
      end
    end

    def apply_sort(scope)
      sort_value = @params[:sort].to_s.strip
      return scope.order(created_at: :desc) if sort_value.blank?

      direction = sort_value.start_with?('-') ? :desc : :asc
      sort_key = sort_value.delete_prefix('-')
      column_name = ALLOWED_SORTS[sort_key]
      raise UnsupportedSortError.new(sort_name: sort_key) unless column_name

      scope.order(column_name => direction, public_id: :asc)
    end

    def paginate(scope)
      page_number = normalized_page_number
      page_size = normalized_page_size
      total_count = scope.count
      total_pages = total_count.zero? ? 0 : (total_count.to_f / page_size).ceil
      @pagination = pagination_metadata(page_number, page_size, total_count, total_pages)
      scope.offset((page_number - 1) * page_size).limit(page_size)
    end

    def normalized_page_number
      raw_page_number = @params.dig(:page, :number)
      return DEFAULT_PAGE_NUMBER if raw_page_number.blank?

      page_number = Integer(raw_page_number, exception: false)
      raise InvalidQueryParameterError.new(field: 'page.number') unless page_number&.positive?

      page_number
    end

    def normalized_page_size
      raw_page_size = @params.dig(:page, :size)
      return DEFAULT_PAGE_SIZE if raw_page_size.blank?

      page_size = Integer(raw_page_size, exception: false)
      raise InvalidQueryParameterError.new(field: 'page.size') unless page_size&.positive?
      raise InvalidQueryParameterError.new(field: 'page.size') if page_size > MAX_PAGE_SIZE

      page_size
    end

    def filters
      raw_filters = @params[:filter]
      return {} unless raw_filters.respond_to?(:to_unsafe_h)

      raw_filters.to_unsafe_h.compact_blank
    end

    def role_scope(scope, filter_value)
      role_values = filter_value.to_s.split(',').map(&:strip).compact_blank
      raise InvalidQueryParameterError.new(field: 'filter.role') if role_values.empty?
      raise InvalidQueryParameterError.new(field: 'filter.role') unless role_codes_supported?(role_values)

      scope.where(role: role_values)
    end

    def boolean_filter_value(filter_value)
      normalized_value = filter_value.to_s.strip.downcase
      return BOOLEAN_FILTER_VALUES.fetch(normalized_value) if BOOLEAN_FILTER_VALUES.key?(normalized_value)

      raise InvalidQueryParameterError.new(field: 'filter.active')
    end

    def pagination_metadata(page_number, page_size, total_count, total_pages)
      { page: page_number, per_page: page_size, total_count:, total_pages: }
    end

    def email_scope(scope, filter_value)
      sanitized_email = ActiveRecord::Base.sanitize_sql_like(filter_value.to_s.strip.downcase)
      scope.where('LOWER(users.email) LIKE ?', "%#{sanitized_email}%")
    end

    def role_codes_supported?(role_values)
      Role.where(code: role_values.uniq).count == role_values.uniq.count
    end
  end
end
