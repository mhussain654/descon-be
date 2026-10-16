# frozen_string_literal: true

class DropTrainingSettings < ActiveRecord::Migration[8.1]
  def up
    drop_table :training_settings
  end

  def down
    create_table :training_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.string :url, null: false
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :training_settings, :singleton_guard, unique: true
  end
end
