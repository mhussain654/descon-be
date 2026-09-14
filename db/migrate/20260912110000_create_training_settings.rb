# frozen_string_literal: true

# A single admin-editable row holding the one external link (e.g. a YouTube
# channel/playlist) candidates are sent to for all training documents and
# videos -- content lives entirely off-platform, this table just points at
# it. `singleton_guard` is always true, and its unique index makes a second
# row impossible at the database level, not just by convention -- mirrors
# CreateAiCallOperationalSettings exactly.
class CreateTrainingSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :training_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.string :url, null: false
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :training_settings, :singleton_guard, unique: true
  end
end
