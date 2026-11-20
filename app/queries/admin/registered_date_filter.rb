# frozen_string_literal: true

module Admin
  # The "registered between" filter shared by the admin candidate list, bulk
  # calls, Mobilization, payments, document reviews, dashboards and reports:
  # `filter[registered_from]` / `filter[registered_to]` (YYYY-MM-DD) bound the
  # candidate's `created_at`, the day they were added or imported. Candidates
  # are imported in batches, so this is how staff look at one batch.
  #
  # Days are calendar days in Pakistan time, where staff work, so a batch
  # imported at 01:00 PKT (20:00 UTC the day before) still belongs to its day.
  class RegisteredDateFilter
    NAMES = %w[registered_from registered_to].freeze
    TIME_ZONE = 'Asia/Karachi'

    # Rejects a malformed date, or a `registered_to` earlier than `registered_from`.
    def self.validate!(values)
      from = date(values['registered_from'], 'registered_from') if values['registered_from'].present?
      to = date(values['registered_to'], 'registered_to') if values['registered_to'].present?
      raise InvalidQueryParameterError.new(field: 'filter.registered_to') if from && to && from > to
    end

    # The open-ended `created_at` range one of the two filters stands for.
    def self.range(name, value)
      day = date(value, name)
      start = Time.find_zone!(TIME_ZONE).local(day.year, day.month, day.day)
      name == 'registered_from' ? (start..) : (..start.end_of_day)
    end

    def self.date(value, name)
      Date.iso8601(value.to_s.strip)
    rescue Date::Error
      raise InvalidQueryParameterError.new(field: "filter.#{name}")
    end
    private_class_method :date
  end
end
