# frozen_string_literal: true

module Users
  class IndexQuery < ApplicationQuery
    DEFAULT_PAGE_NUMBER = 1
    DEFAULT_PAGE_SIZE = 20
    MAX_PAGE_SIZE = 100
    ALLOWED_FILTERS = %w[active email role].freeze
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
        scope.where(active: ActiveModel::Type::Boolean.new.cast(filter_value))
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
      @pagination = pagination_data(page_number:, page_size:, total_count:, total_pages:)

      scope.offset((page_number - 1) * page_size).limit(page_size)
    end

    def normalized_page_number
      [@params.dig(:page, :number).to_i, DEFAULT_PAGE_NUMBER].max
    end

    def normalized_page_size
      requested_size = @params.dig(:page, :size).to_i
      page_size = requested_size.positive? ? requested_size : DEFAULT_PAGE_SIZE
      [page_size, MAX_PAGE_SIZE].min
    end

    def filters
      raw_filters = @params[:filter]
      return {} unless raw_filters.respond_to?(:to_unsafe_h)

      raw_filters.to_unsafe_h.compact_blank
    end

    def email_scope(scope, filter_value)
      sanitized_email = ActiveRecord::Base.sanitize_sql_like(filter_value.to_s.strip.downcase)
      scope.where('LOWER(users.email) LIKE ?', "%#{sanitized_email}%")
    end

    def role_scope(scope, filter_value)
      role_values = filter_value.to_s.split(',').map(&:strip).compact_blank
      scope.where(role: role_values)
    end

    def pagination_data(page_number:, page_size:, total_count:, total_pages:)
      {
        page: page_number,
        per_page: page_size,
        total_count:,
        total_pages:
      }
    end
  end
end
