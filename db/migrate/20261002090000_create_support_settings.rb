# frozen_string_literal: true

# A single admin-editable row holding the support/helpline number candidates
# can call from the app's "Help & support" action. Mirrors
# CreateTrainingSettings exactly: `singleton_guard` is always true and its
# unique index makes a second row impossible at the database level.
# `phone_number` stays nullable -- there is no sensible default for a real
# support line, so the candidate action is simply unavailable until set.
class CreateSupportSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :support_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.string :phone_number
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :support_settings, :singleton_guard, unique: true
  end
end
