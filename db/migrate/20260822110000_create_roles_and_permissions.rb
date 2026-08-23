# frozen_string_literal: true

class CreateRolesAndPermissions < ActiveRecord::Migration[8.1]
  SYSTEM_ROLES = [
    { code: 'admin' },
    { code: 'staff' }
  ].freeze

  SYSTEM_PERMISSIONS = [
    { code: 'manage_staff_users' },
    { code: 'manage_roles_permissions' },
    { code: 'manage_candidates' },
    { code: 'manage_candidate_assignments' },
    { code: 'manage_candidate_documents' },
    { code: 'manage_workflow' },
    { code: 'manage_payments' },
    { code: 'manage_communications' },
    { code: 'view_audit_events' }
  ].freeze

  ROLE_PERMISSION_MAP = {
    'admin' => SYSTEM_PERMISSIONS.map { |permission| permission.fetch(:code) },
    'staff' => %w[
      manage_candidates
      manage_candidate_assignments
      manage_candidate_documents
      manage_workflow
      manage_payments
      manage_communications
    ]
  }.freeze

  def up
    create_table :roles do |t|
      t.string :code, null: false
      t.boolean :system_defined, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :roles, :code, unique: true

    create_table :permissions do |t|
      t.string :code, null: false
      t.boolean :system_defined, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :permissions, :code, unique: true

    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: { on_delete: :cascade }
      t.references :permission, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :role_permissions, %i[role_id permission_id], unique: true

    insert_system_roles_and_permissions

    execute <<~SQL.squish
      UPDATE users
      SET role = 'staff'
      WHERE role = 'member'
    SQL

    change_column_default :users, :role, from: 'member', to: 'staff'
    add_foreign_key :users, :roles, column: :role, primary_key: :code
  end

  def down
    remove_foreign_key :users, column: :role
    change_column_default :users, :role, from: 'staff', to: 'member'

    execute <<~SQL.squish
      UPDATE users
      SET role = 'member'
      WHERE role = 'staff'
    SQL

    drop_table :role_permissions
    drop_table :permissions
    drop_table :roles
  end

  private

  def insert_system_roles_and_permissions
    now = connection.quote(Time.current)

    execute <<~SQL.squish
      INSERT INTO roles (code, system_defined, active, created_at, updated_at)
      VALUES #{SYSTEM_ROLES.map { |role| role_values(role, now) }.join(', ')}
      ON CONFLICT (code) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO permissions (code, system_defined, active, created_at, updated_at)
      VALUES #{SYSTEM_PERMISSIONS.map { |permission| role_values(permission, now) }.join(', ')}
      ON CONFLICT (code) DO NOTHING
    SQL

    ROLE_PERMISSION_MAP.each do |role_code, permission_codes|
      permission_codes.each do |permission_code|
        execute <<~SQL.squish
          INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
          SELECT roles.id, permissions.id, #{now}, #{now}
          FROM roles, permissions
          WHERE roles.code = #{connection.quote(role_code)}
            AND permissions.code = #{connection.quote(permission_code)}
          ON CONFLICT (role_id, permission_id) DO NOTHING
        SQL
      end
    end
  end

  def role_values(record, now)
    [
      connection.quote(record.fetch(:code)),
      connection.quote(true),
      connection.quote(true),
      now,
      now
    ].join(', ').prepend('(').concat(')')
  end
end
