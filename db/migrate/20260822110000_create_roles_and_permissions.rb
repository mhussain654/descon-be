# frozen_string_literal: true

class CreateRolesAndPermissions < ActiveRecord::Migration[8.1]
  SYSTEM_ROLES = [
    { code: 'admin' },
    { code: 'hr' },
    { code: 'mps' },
    { code: 'finance' },
    { code: 'management' }
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
    { code: 'view_candidates' },
    { code: 'view_candidate_assignments' },
    { code: 'view_candidate_documents' },
    { code: 'view_workflow' },
    { code: 'view_payments' },
    { code: 'view_communications' },
    { code: 'view_audit_events' }
  ].freeze

  ROLE_PERMISSION_MAP = {
    'admin' => SYSTEM_PERMISSIONS.map { |permission| permission.fetch(:code) },
    'hr' => %w[
      manage_candidates
      manage_candidate_documents
      manage_communications
      view_candidate_assignments
      view_workflow
    ],
    'mps' => %w[
      view_candidates
      manage_candidate_assignments
      manage_candidate_documents
      manage_workflow
      manage_communications
    ],
    'finance' => %w[
      view_candidates
      view_candidate_assignments
      view_candidate_documents
      view_workflow
      manage_payments
    ],
    'management' => %w[
      view_candidates
      view_candidate_assignments
      view_candidate_documents
      view_workflow
      view_payments
      view_communications
      view_audit_events
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
    add_check_constraint :roles, "code ~ '^[a-z0-9_]+$'", name: 'roles_code_format'

    create_table :permissions do |t|
      t.string :code, null: false
      t.boolean :system_defined, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :permissions, :code, unique: true
    add_check_constraint :permissions, "code ~ '^[a-z0-9_]+$'", name: 'permissions_code_format'

    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: { on_delete: :cascade }
      t.references :permission, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :role_permissions, %i[role_id permission_id], unique: true

    insert_system_roles_and_permissions

    execute <<~SQL.squish
      UPDATE users
      SET role = 'hr'
      WHERE role IN ('member', 'staff')
    SQL

    change_column_default :users, :role, from: 'member', to: 'hr'
    add_foreign_key :users, :roles, column: :role, primary_key: :code
  end

  def down
    remove_foreign_key :users, column: :role
    change_column_default :users, :role, from: 'hr', to: 'member'

    execute <<~SQL.squish
      UPDATE users
      SET role = 'member'
      WHERE role IN ('hr', 'mps', 'finance', 'management')
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
