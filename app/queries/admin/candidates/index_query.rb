# frozen_string_literal: true

module Admin
  module Candidates
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_FILTERS = %w[status country_code project_code craft_code].freeze
      ALLOWED_SORTS = %w[created_at full_name reference_number].freeze
      attr_reader :pagination, :applied_filters

      def initialize(scope:, params:)
        super()
        @scope = scope
        @params = params
        @pagination = {}
        @applied_filters = {}
      end

      def call
        paginate(apply_sort(apply_filters(apply_search(preloaded_scope))))
      end

      private

      def preloaded_scope
        @scope.includes(candidate_assignments: %i[country project craft current_workflow_stage])
      end

      def apply_search(scope)
        value = @params[:search].to_s.strip
        return scope if value.blank?

        normalized_cnic = ::Candidates::CnicNormalizer.call(value)
        normalized_passport = value.upcase.gsub(/\s+/, '')
        normalized_reference = value.upcase
        name_match = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
        matching_search_scope(scope, name_match:, normalized_cnic:, normalized_passport:, normalized_reference:)
      end

      def matching_search_scope(scope, name_match:, normalized_cnic:, normalized_passport:, normalized_reference:)
        values = search_values(name_match:, normalized_cnic:, normalized_passport:, normalized_reference:)
        scope.left_joins(:candidate_assignments).where(search_clause, values).distinct
      end

      def search_clause
        <<~SQL.squish
          candidates.full_name ILIKE :name OR candidates.cnic = :cnic OR
          candidates.passport_number = :passport OR candidate_assignments.reference_number = :reference
        SQL
      end

      def search_values(name_match:, normalized_cnic:, normalized_passport:, normalized_reference:)
        { name: name_match, cnic: normalized_cnic, passport: normalized_passport, reference: normalized_reference }
      end

      def apply_filters(scope)
        filters.reduce(scope) { |current, (name, value)| filter_scope(current, name, value) }
      end

      def filters
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.compact_blank.tap do |values|
          invalid = values.keys - ALLOWED_FILTERS
          raise UnsupportedFilterError.new(filter_name: invalid.first) if invalid.any?

          @applied_filters = values
        end
      end

      def filter_scope(scope, name, value)
        if name == 'status'
          status = value.to_s.strip.downcase
          raise InvalidQueryParameterError.new(field: 'filter.status') unless WorkflowStage.exists?(code: status)

          return scope.where(status_code: status)
        end

        scope.joins(:candidate_assignments).where(
          candidate_assignments: { reference_column(name) => reference_id(name, value) }
        )
      end

      def reference_column(filter_name)
        { 'country_code' => :country_id, 'project_code' => :project_id, 'craft_code' => :craft_id }.fetch(filter_name)
      end

      def reference_id(filter_name, value)
        model = { 'country_code' => Country, 'project_code' => Project, 'craft_code' => Craft }.fetch(filter_name)
        record = model.find_by(code: value.to_s.strip.downcase)
        raise InvalidQueryParameterError.new(field: "filter.#{filter_name}") if record.blank?

        record.id
      end

      def apply_sort(scope)
        raw = @params[:sort].to_s.strip
        return scope.order(created_at: :desc, public_id: :asc) if raw.blank?

        direction = raw.start_with?('-') ? :desc : :asc
        field = raw.delete_prefix('-')
        raise UnsupportedSortError.new(sort_name: field) unless ALLOWED_SORTS.include?(field)

        if field == 'reference_number'
          return scope.order(candidate_assignments: { reference_number: direction }, candidates: { public_id: :asc })
        end

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

        result = Integer(value, exception: false)
        raise InvalidQueryParameterError.new(field:) unless result&.positive?

        result
      end
    end
  end
end
