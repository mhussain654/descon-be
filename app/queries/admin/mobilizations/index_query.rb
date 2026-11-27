# frozen_string_literal: true

module Admin
  module Mobilizations
    # The admin Mobilization list: every candidate whose flight staff have
    # recorded (on their current assignment), from booking through to
    # mobilization, so staff can track one day's departures and chase missing
    # boarding passes. Scoped to the candidates the staff member may see.
    class IndexQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 20
      MAX_PAGE_SIZE = 100
      ALLOWED_FILTERS = (%w[flight_date boarding_pass status country_code] + FilterScope::MOBILIZED_DATE_FILTERS +
                         RegisteredDateFilter::NAMES).freeze
      ALLOWED_SORTS = %w[departure_at -departure_at].freeze

      attr_reader :pagination, :applied_filters

      def initialize(candidate_scope:, params:)
        super()
        @candidate_scope = candidate_scope
        @params = params
        @pagination = {}
        @applied_filters = {}
      end

      def call
        paginate(apply_sort(filtered_scope(filters)))
          .includes(:ticket_attachment, candidate_assignment: %i[candidate country project craft])
      end

      # Counts for the summary cards and filter options. Each group is counted
      # under every active filter except its own, so its options always add up.
      def summary
        {
          total: filtered_scope(filters).count,
          boarding_pass: counts_by(FilterScope::BOARDING_PASS_STATES, 'boarding_pass'),
          status: counts_by(FilterScope::STATUS_STATES, 'status')
        }
      end

      private

      def counts_by(states, filter_name)
        scope = filtered_scope(filters.except(filter_name))
        states.to_h { |state| [state.to_sym, FilterScope.call(scope, filter_name, state).count] }
      end

      def filtered_scope(active_filters)
        active_filters.reduce(apply_search(base_scope)) { |scope, (name, value)| FilterScope.call(scope, name, value) }
      end

      def base_scope
        CandidateFlightDetail
          .joins(candidate_assignment: :candidate)
          .where(candidate_assignment_id: current_assignment_ids)
      end

      # Only each visible candidate's latest assignment, so a restarted
      # candidate's old flight never shows.
      def current_assignment_ids
        CandidateAssignment
          .where(candidate_id: @candidate_scope.select(:id))
          .where(<<~SQL.squish)
            candidate_assignments.id = (
              SELECT latest.id FROM candidate_assignments latest
              WHERE latest.candidate_id = candidate_assignments.candidate_id
              ORDER BY latest.created_at DESC, latest.id DESC LIMIT 1
            )
          SQL
          .select(:id)
      end

      def apply_search(scope)
        value = @params[:search].to_s.strip
        return scope if value.blank?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
        number = ::Candidates::RegistrationNumberParser.search_number(value)
        scope.where(
          'candidates.full_name ILIKE :like OR candidate_assignments.registration_number = :number ' \
          'OR candidate_flight_details.flight_number ILIKE :like',
          like:, number:
        )
      end

      def filters
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.compact_blank.tap do |values|
          invalid = values.keys - ALLOWED_FILTERS
          raise UnsupportedFilterError.new(filter_name: invalid.first) if invalid.any?

          RegisteredDateFilter.validate!(values)
          FilterScope.validate_mobilized_range!(values)
          @applied_filters = values
        end
      end

      def apply_sort(scope)
        raw = @params[:sort].to_s.strip.presence || '-departure_at'
        raise UnsupportedSortError.new(sort_name: raw.delete_prefix('-')) unless ALLOWED_SORTS.include?(raw)

        direction = raw.start_with?('-') ? :desc : :asc
        scope.order(flight_departure_at: direction, public_id: :asc)
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
