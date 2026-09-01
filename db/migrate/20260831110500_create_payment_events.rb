# frozen_string_literal: true

class CreatePaymentEvents < ActiveRecord::Migration[8.1]
  def change
    create_payment_events_table
    add_payment_event_indexes
    add_payment_event_constraints
  end

  private

  def create_payment_events_table
    create_table :payment_events do |t|
      add_payment_event_references(t)
      payment_event_required_strings.each { |field| t.string field, null: false }
      payment_event_optional_strings.each { |field| t.string field }
      payment_event_datetime_fields(t)
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
  end

  def add_payment_event_references(table)
    table.references :payment, null: false, foreign_key: true
    table.references :candidate_assignment, null: false, foreign_key: true
    table.references :actor, foreign_key: { to_table: :users }
  end

  def payment_event_required_strings
    %i[provider_code event_source event_type event_key]
  end

  def payment_event_optional_strings
    %i[request_id provider_order_id provider_transaction_id provider_status_code]
  end

  def payment_event_datetime_fields(table)
    table.datetime :occurred_at, null: false
    table.datetime :processed_at
  end

  def add_payment_event_indexes
    add_index :payment_events, %i[provider_code event_key], unique: true
    add_index :payment_events,
              %i[candidate_assignment_id occurred_at],
              name: 'index_payment_events_on_assignment_and_occurred_at'
  end

  def add_payment_event_constraints
    add_check_constraint :payment_events,
                         "provider_code ~ '^[a-z0-9_]+$'",
                         name: 'payment_events_provider_code_format'
    add_check_constraint :payment_events,
                         "event_source ~ '^[a-z0-9_]+$'",
                         name: 'payment_events_event_source_format'
    add_check_constraint :payment_events,
                         "event_type ~ '^[a-z0-9_]+$'",
                         name: 'payment_events_event_type_format'
  end
end
