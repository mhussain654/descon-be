# frozen_string_literal: true

# Optional display names a developer sets in admin (Reference data). Empty
# means the built-in translated name is used.
class AddNameOverridesToWorkflowStages < ActiveRecord::Migration[8.1]
  def change
    change_table :workflow_stages, bulk: true do |t|
      t.string :name_en, limit: 120
      t.string :name_ur, limit: 120
    end
  end
end
