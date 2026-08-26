# frozen_string_literal: true

class AddCandidateRegistryFields < ActiveRecord::Migration[8.1]
  def change
    change_table :candidates, bulk: true do |table|
      table.string :status_code, null: false, default: 'registered'
      table.boolean :active, null: false, default: true
    end

    add_check_constraint :candidates, "status_code ~ '^[a-z0-9_]+$'", name: 'candidates_status_code_format'
  end
end
