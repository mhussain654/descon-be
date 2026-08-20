# frozen_string_literal: true

class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :jti, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :revoked_at
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :sessions, :public_id, unique: true
    add_index :sessions, :jti, unique: true
    add_index :sessions, %i[user_id revoked_at]
  end
end
