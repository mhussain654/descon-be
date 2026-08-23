# frozen_string_literal: true

class CreatePaymentsCommunicationsAndAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_payments
    create_communications
    create_audit_events
  end

  private

  def create_payments
    create_table :payments do |t|
      t.string :public_id, null: false
      t.references :candidate_assignment, null: false, foreign_key: true
      t.string :payment_type_code, null: false
      t.string :status_code, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency_code, null: false
      t.string :external_reference
      t.datetime :paid_at
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.text :note

      t.timestamps
    end

    add_index :payments, :public_id, unique: true
    add_index :payments,
              %i[candidate_assignment_id status_code created_at],
              name: 'index_payments_on_assignment_status_created_at'
    add_index :payments, :external_reference, unique: true, where: 'external_reference IS NOT NULL'
  end

  def create_communications
    create_table :communications do |t|
      t.string :public_id, null: false
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :initiated_by, foreign_key: { to_table: :users }
      t.string :channel_code, null: false
      t.string :direction_code, null: false
      t.string :status_code, null: false
      t.string :template_code
      t.string :locale, null: false, default: 'en'
      t.string :recipient_masked
      t.string :provider_reference
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.string :error_code

      t.timestamps
    end

    add_index :communications, :public_id, unique: true
    add_index :communications,
              %i[candidate_assignment_id channel_code created_at],
              name: 'index_communications_on_assignment_channel_created_at'
    add_index :communications, :provider_reference
  end

  def create_audit_events
    create_table :audit_events do |t|
      t.references :candidate, foreign_key: true
      t.references :candidate_assignment, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.string :action_code, null: false
      t.string :reason_code
      t.text :note
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :audit_events, %i[entity_type entity_id occurred_at], name: 'index_audit_events_on_entity_and_occurred_at'
    add_index :audit_events,
              %i[candidate_assignment_id occurred_at],
              name: 'index_audit_events_on_assignment_and_occurred_at'
    add_index :audit_events, %i[candidate_id occurred_at], name: 'index_audit_events_on_candidate_and_occurred_at'
    add_index :audit_events, %i[actor_id occurred_at], name: 'index_audit_events_on_actor_and_occurred_at'
  end
end
