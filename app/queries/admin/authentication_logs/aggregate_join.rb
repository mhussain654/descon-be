# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # LEFT JOINs a grouped subquery (per-candidate or per-user counts) onto
    # `table` as `alias_name`, built with Arel rather than an SQL string.
    module AggregateJoin
      def self.call(table:, relation:, alias_name:, foreign_key:)
        subquery = relation.arel.as(alias_name)
        table.join(subquery, Arel::Nodes::OuterJoin).on(subquery[foreign_key].eq(table[:id])).join_sources
      end
    end
  end
end
