# frozen_string_literal: true

class AddOnboardingFeeSettings < ActiveRecord::Migration[8.1]
  def change
    create_default_setting
    add_candidate_override
  end

  private

  def create_default_setting
    create_setting_table
    add_index :onboarding_fee_settings, :singleton_guard, unique: true
    add_check_constraint :onboarding_fee_settings, 'singleton_guard = true', name: 'onboarding_fee_singleton'
    add_check_constraint :onboarding_fee_settings, 'amount > 0', name: 'onboarding_fee_positive'
  end

  def create_setting_table
    create_table :onboarding_fee_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :lock_version, null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end

  def add_candidate_override
    add_column :candidate_assignments, :onboarding_fee_amount, :decimal, precision: 10, scale: 2
    add_column :candidate_assignments, :fee_version, :integer, null: false, default: 0
    add_check_constraint :candidate_assignments, 'onboarding_fee_amount IS NULL OR onboarding_fee_amount > 0',
                         name: 'candidate_onboarding_fee_positive'
  end
end
