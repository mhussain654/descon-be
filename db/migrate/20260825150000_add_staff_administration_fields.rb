# frozen_string_literal: true

class AddStaffAdministrationFields < ActiveRecord::Migration[8.1]
  STAFF_STATES = %w[invited active suspended].freeze
  ACTIVE_STATE_CONSTRAINT = <<~SQL.squish.freeze
    (staff_state = 'active' AND active = TRUE) OR
      (staff_state IN ('invited', 'suspended') AND active = FALSE)
  SQL

  def up
    add_user_staff_fields!
    add_reference :users, :invited_by, foreign_key: { to_table: :users }
    add_audit_event_fields!
    backfill_staff_state!
    add_staff_indexes!
    add_staff_state_constraints!
  end

  def down
    remove_check_constraint :users, name: 'users_staff_state_matches_active'
    remove_check_constraint :users, name: 'users_staff_state'
    remove_staff_indexes!
    remove_audit_event_fields!
    remove_reference :users, :invited_by, foreign_key: { to_table: :users }
    remove_user_staff_fields!
  end

  private

  def add_user_staff_fields!
    change_table :users, bulk: true do |table|
      table.string :staff_state, null: false, default: 'active'
      table.string :invitation_token_digest
      table.datetime :invitation_sent_at
      table.datetime :invitation_expires_at
      table.datetime :invitation_accepted_at
    end
  end

  def add_audit_event_fields!
    change_table :audit_events, bulk: true do |table|
      table.string :request_id
      table.jsonb :metadata, null: false, default: {}
    end
  end

  def backfill_staff_state!
    execute <<~SQL.squish
      UPDATE users
      SET staff_state = CASE
        WHEN active THEN 'active'
        ELSE 'suspended'
      END
    SQL
  end

  def add_staff_indexes!
    add_index :users, :invitation_token_digest, unique: true
    add_index :users, :staff_state
    add_index :audit_events, :request_id
  end

  def add_staff_state_constraints!
    add_check_constraint(
      :users,
      "staff_state IN ('#{STAFF_STATES.join("','")}')",
      name: 'users_staff_state'
    )
    add_check_constraint(
      :users,
      ACTIVE_STATE_CONSTRAINT,
      name: 'users_staff_state_matches_active'
    )
  end

  def remove_staff_indexes!
    remove_index :audit_events, :request_id
    remove_index :users, :staff_state
    remove_index :users, :invitation_token_digest
  end

  def remove_audit_event_fields!
    change_table :audit_events, bulk: true do |table|
      table.remove :metadata
      table.remove :request_id
    end
  end

  def remove_user_staff_fields!
    change_table :users, bulk: true do |table|
      table.remove :invitation_accepted_at
      table.remove :invitation_expires_at
      table.remove :invitation_sent_at
      table.remove :invitation_token_digest
      table.remove :staff_state
    end
  end
end
