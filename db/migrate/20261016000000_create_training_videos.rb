# frozen_string_literal: true

class CreateTrainingVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :training_videos do |t|
      t.string :title_en, null: false
      t.string :title_ur, null: false
      t.text :description_en
      t.text :description_ur
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :training_videos, %i[published position id]
    add_check_constraint :training_videos, 'position >= 0', name: 'training_videos_position_nonnegative'
  end
end
