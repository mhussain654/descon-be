# frozen_string_literal: true

module Maintenance
  # Orders a set of tables to be emptied so each comes before every table of
  # the set it references (children first), using the database's own foreign
  # keys, and finds tables outside the set that still point into it.
  class PurgedTableOrder
    class CycleError < StandardError
    end

    def initialize(tables, connection: ActiveRecord::Base.connection)
      @tables = tables
      @connection = connection
    end

    # Raises CycleError if the foreign keys form a cycle (a new table would
    # then need a decision).
    def ordered
      remaining = @tables.dup
      ordered = []
      until remaining.empty?
        ready = remaining.reject { |table| referenced_by_others?(table, remaining) }
        raise CycleError, "Foreign key cycle among: #{remaining.join(', ')}" if ready.empty?

        ordered.concat(ready)
        remaining -= ready
      end
      ordered
    end

    # "table.column" for every foreign key from a table outside the set into it.
    def outside_references
      (@connection.tables - @tables).flat_map do |table|
        @connection.foreign_keys(table).select { |key| @tables.include?(key.to_table) }
                   .map { |key| "#{table}.#{key.column}" }
      end
    end

    private

    def referenced_by_others?(table, remaining)
      (remaining - [table]).any? do |other|
        @connection.foreign_keys(other).any? { |key| key.to_table == table }
      end
    end
  end
end
