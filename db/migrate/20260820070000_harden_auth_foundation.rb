# frozen_string_literal: true

class HardenAuthFoundation < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.boolean :active, null: false, default: true
      t.integer :failed_attempts, null: false, default: 0
      t.string :unlock_token
      t.datetime :locked_at
    end

    remove_index :users, :email
    add_index :users, 'LOWER(email)', unique: true, name: 'index_users_on_lower_email'
    add_index :users, :unlock_token, unique: true

    add_foreign_key :refresh_tokens, :refresh_tokens, column: :replaced_by_id
    add_index :refresh_tokens,
              %i[session_id revoked_at rotated_at expires_at],
              name: 'index_refresh_tokens_on_active_lookup'
  end
end
