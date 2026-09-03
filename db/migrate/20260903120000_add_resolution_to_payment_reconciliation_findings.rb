# frozen_string_literal: true

class AddResolutionToPaymentReconciliationFindings < ActiveRecord::Migration[8.1]
  def change
    add_resolution_columns
    backfill_public_id
    change_column_null :payment_reconciliation_findings, :public_id, false
  end

  private

  def add_resolution_columns
    change_table :payment_reconciliation_findings, bulk: true do |table|
      table.string :public_id
      table.datetime :resolved_at
      table.bigint :resolved_by_id
      table.text :resolution_note
      table.index :public_id, unique: true
    end
    add_foreign_key :payment_reconciliation_findings, :users, column: :resolved_by_id
  end

  def backfill_public_id
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE payment_reconciliation_findings SET public_id = gen_random_uuid()::text WHERE public_id IS NULL
        SQL
      end
    end
  end
end
