# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # `sort` handling shared by the Authentication page's lists: a column from
    # the list's own allowlist (Arel nodes, so no request text ever reaches the
    # SQL), `-` prefix for descending, rows without a value (for example never
    # signed in) always last. Defaults to `-last_login_at`.
    module Sort
      DEFAULT = '-last_login_at'

      def self.apply(scope, value, columns:)
        value = value.to_s.strip.presence || DEFAULT
        field = value.delete_prefix('-')
        column = columns[field] || raise(UnsupportedSortError.new(sort_name: field))
        ordering = value.start_with?('-') ? column.desc : column.asc

        scope.order(ordering.nulls_last, id: :desc)
      end

      # Turns `{ 'field' => 'sql.column' }` into the Arel nodes `apply` expects.
      def self.columns(definitions)
        definitions.transform_values { |sql| Arel.sql(sql) }.freeze
      end
    end
  end
end
