# frozen_string_literal: true

# A single admin-editable row overriding AiCalls::Configuration's 5
# ENV-driven operational knobs (cooldown, daily limit, admin rate limit,
# calling hours, max call duration) -- see the plan's "DB-driven,
# admin-editable rate limits". Every column is nullable: an environment
# that never touches the admin UI keeps its existing ENV-driven behavior
# unchanged. `singleton_guard` is always true, and its unique index makes a
# second row impossible at the database level, not just by convention.
class CreateAiCallOperationalSettings < ActiveRecord::Migration[8.1]
  NON_NEGATIVE_COLUMNS = %w[
    outbound_trigger_cooldown_minutes daily_outbound_call_limit admin_trigger_rate_limit_per_hour
    max_call_duration_minutes
  ].freeze
  HOUR_RANGE_COLUMNS = %w[calling_hours_start calling_hours_end].freeze

  def change
    create_ai_call_operational_settings_table
    add_singleton_index
    add_range_constraints
  end

  private

  def create_ai_call_operational_settings_table
    create_table :ai_call_operational_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      (NON_NEGATIVE_COLUMNS + HOUR_RANGE_COLUMNS).each { |column| t.integer column }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end

  def add_singleton_index
    add_index :ai_call_operational_settings, :singleton_guard, unique: true
  end

  def add_range_constraints
    NON_NEGATIVE_COLUMNS.each do |column|
      add_check_constraint :ai_call_operational_settings, "#{column} >= 0",
                           name: "ai_call_operational_settings_#{column}_non_negative"
    end

    HOUR_RANGE_COLUMNS.each do |column|
      add_check_constraint :ai_call_operational_settings, "#{column} IS NULL OR #{column} BETWEEN 0 AND 23",
                           name: "ai_call_operational_settings_#{column}_range"
    end
  end
end
