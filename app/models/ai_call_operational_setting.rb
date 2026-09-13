# frozen_string_literal: true

# The single admin-editable row of AI-call operational limits (cooldown,
# daily/hourly caps, calling hours, max duration) -- see AiCalls::Configuration,
# which checks this row before falling back to its ENV-driven defaults.
# `singleton_guard` is always true; its unique index makes a second row
# impossible at the database level (see the migration), not just by
# convention -- #current is the only supported way to obtain the row.
class AiCallOperationalSetting < ApplicationRecord
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :singleton_guard, inclusion: { in: [true] }
  validates :outbound_trigger_cooldown_minutes, :daily_outbound_call_limit, :admin_trigger_rate_limit_per_hour,
            :max_call_duration_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :calling_hours_start, :calling_hours_end,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 },
            allow_nil: true

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it if this is the first access
  # anywhere (e.g. a freshly schema-loaded test database, which never
  # replays a migration's data). Race-safe: a concurrent first access loses
  # the unique-index race and simply reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  private

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end
