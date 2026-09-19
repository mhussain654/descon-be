# frozen_string_literal: true

module Admin
  module Reports
    # Resolves the admin dashboard's filter[country_code]/filter[project_code]/
    # filter[craft_code] params (the same vocabulary and validation behavior
    # as Admin::Candidates::IndexQuery -- an unknown code always raises
    # InvalidQueryParameterError, never silently matches nothing) into a
    # plain Candidate scope.
    #
    # Deliberately does NOT reuse IndexQuery's approach of filtering through
    # an already-joined `current_assignments` alias: every dashboard
    # aggregation query (StatusSummaryQuery, ConversionQuery, etc.) already
    # performs its own CurrentAssignmentJoin internally, and handing them a
    # scope that already carries a `current_assignments` join would join the
    # same alias twice, which Postgres rejects. Resolving to
    # `Candidate.where(id: <subquery>)` instead composes safely with a
    # second, independent join downstream (verified via
    # dashboards_spec.rb's filtered-count request specs, not just by
    # inspection).
    class DashboardFilterResolution < ApplicationQuery
      ALLOWED_FILTERS = %w[country_code project_code craft_code].freeze
      REFERENCE_MODEL = { 'country_code' => Country, 'project_code' => Project, 'craft_code' => Craft }.freeze
      REFERENCE_COLUMN = {
        'country_code' => 'current_assignments.country_id',
        'project_code' => 'current_assignments.project_id',
        'craft_code' => 'current_assignments.craft_id'
      }.freeze

      def initialize(params:)
        super()
        @params = params
      end

      def call
        filters.reduce(Candidate.all) { |scope, (name, value)| filter_scope(scope, name, value) }
      end

      private

      def filters
        raw = @params[:filter]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.compact_blank.tap do |values|
          invalid = values.keys - ALLOWED_FILTERS
          raise UnsupportedFilterError.new(filter_name: invalid.first) if invalid.any?
        end
      end

      def filter_scope(scope, name, value)
        id = reference_id(name, value)
        matching_ids = CurrentAssignmentJoin.call(scope: Candidate.all)
                                            .where(REFERENCE_COLUMN.fetch(name) => id)
                                            .select('candidates.id')
        scope.where(id: matching_ids)
      end

      def reference_id(filter_name, value)
        record = REFERENCE_MODEL.fetch(filter_name).find_by(code: value.to_s.strip.downcase)
        raise InvalidQueryParameterError.new(field: "filter.#{filter_name}") if record.blank?

        record.id
      end
    end
  end
end
