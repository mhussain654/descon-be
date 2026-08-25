# frozen_string_literal: true

class CreateAuthenticationEvents < ActiveRecord::Migration[8.1]
  def change
    create_authentication_events_table
    add_authentication_event_indexes
  end

  private

  def create_authentication_events_table
    create_table :authentication_events do |t|
      add_subject_columns(t)
      add_event_columns(t)
      t.timestamps
    end
  end

  def add_authentication_event_indexes
    add_index :authentication_events, :event_code
    add_index :authentication_events, :occurred_at
  end

  def add_subject_columns(table)
    table.references :user, null: true, foreign_key: true
    table.references :session, null: true, foreign_key: true
  end

  def add_event_columns(table)
    table.string :event_code, null: false
    table.string :request_id, null: false
    table.string :identifier_masked
    table.string :ip_address
    table.string :user_agent
    table.jsonb :metadata, null: false, default: {}
    table.datetime :occurred_at, null: false
  end
end
