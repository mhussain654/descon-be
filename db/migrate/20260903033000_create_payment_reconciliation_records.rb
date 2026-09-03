# frozen_string_literal: true

class CreatePaymentReconciliationRecords < ActiveRecord::Migration[8.1]
  def change
    create_runs
    create_findings
  end

  private

  def create_runs
    create_table :payment_reconciliation_runs do |table|
      table.date :run_date, null: false
      table.string :status_code, null: false, default: 'processing'
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.bigint :initiated_by_id
      table.jsonb :summary, null: false, default: {}
      table.timestamps
    end
    add_index :payment_reconciliation_runs, :run_date, unique: true
    add_foreign_key :payment_reconciliation_runs, :users, column: :initiated_by_id
  end

  def create_findings
    create_table :payment_reconciliation_findings do |table|
      table.references :payment_reconciliation_run, null: false, foreign_key: true
      table.references :payment, foreign_key: true
      table.string :finding_code, null: false
      table.string :state_code, null: false, default: 'open'
      table.jsonb :details, null: false, default: {}
      table.timestamps
    end
    add_index :payment_reconciliation_findings,
              %i[payment_reconciliation_run_id payment_id finding_code],
              unique: true,
              name: 'idx_payment_reconciliation_findings_unique'
    add_index :payment_reconciliation_findings, %i[state_code created_at]
  end
end
