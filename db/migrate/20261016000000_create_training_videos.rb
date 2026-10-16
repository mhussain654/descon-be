# frozen_string_literal: true

class CreateTrainingVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :training_videos do |table|
      define_columns(table)
      table.timestamps
    end
    add_index :training_videos, %i[published position id]
    add_check_constraint :training_videos, 'position >= 0', name: 'training_videos_position_nonnegative'
  end

  private

  def define_columns(table)
    table.string :title_en, null: false
    table.string :title_ur, null: false
    table.text :description_en
    table.text :description_ur
    table.integer :position, null: false, default: 0
    table.boolean :published, null: false, default: false
    table.references :created_by, null: false, foreign_key: { to_table: :users }
  end
end
